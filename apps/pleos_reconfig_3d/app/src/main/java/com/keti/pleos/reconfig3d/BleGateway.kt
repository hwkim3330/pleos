package com.keti.pleos.reconfig3d

import android.annotation.SuppressLint
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.ArrayDeque
import java.util.UUID

/**
 * Direct BLE link to the 7-inch controller, written against the platform API rather
 * than a plugin. The confirmed rig is tablet -> 7-inch -> Path1/Path2, all BLE, with
 * no host bridge in it, so this app owns the GATT connection itself.
 *
 * Android allows exactly one outstanding GATT operation per connection and silently
 * drops the rest, so every write, descriptor write and MTU request goes through one
 * queue. Firing them off as they arrive appears to work until the first burst -- and a
 * switch fault is a burst of three writes.
 */
class BleGateway(context: Context) {

    private companion object {
        const val TAG = "BleGateway"
        const val DEVICE_NAME = "PLEOS-RECONFIG"
        val SERVICE_UUID: UUID = UUID.fromString("7d2f0001-7c7a-4f7b-9b51-0af9a281d110")
        val CONTROL_UUID: UUID = UUID.fromString("7d2f0002-7c7a-4f7b-9b51-0af9a281d110")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        const val RETRY_MS = 1_500L
        const val SYNC_MIN_GAP_MS = 600L
    }

    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val handler = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow(LinkState())
    val state: StateFlow<LinkState> = _state.asStateFlow()

    private val _log = MutableSharedFlow<LogEntry>(extraBufferCapacity = 128)
    val log: SharedFlow<LogEntry> = _log.asSharedFlow()

    private val channels = linkedMapOf<String, String>()
    private val pathNodes = linkedMapOf("1" to false, "2" to false)
    private var mode = "--"
    private var sequence = 0
    private var ioNode = false

    private var gatt: BluetoothGatt? = null
    private var control: BluetoothGattCharacteristic? = null
    private var scanning = false
    private var lastSyncAt = 0L
    private var released = false

    /** Pending GATT operations; head is in flight. */
    private val pending = ArrayDeque<() -> Boolean>()
    private var inFlight = false

    private fun note(kind: EntryKind, title: String, detail: String = "") {
        _log.tryEmit(LogEntry(System.currentTimeMillis(), kind, title, detail))
    }

    private fun publish() {
        _state.value = LinkState(
            gatewayOnline = control != null,
            mode = mode,
            sequence = sequence,
            ioNodeOnline = ioNode,
            channels = LinkedHashMap(channels),
            pathNodesOnline = LinkedHashMap(pathNodes),
        )
    }

    @SuppressLint("MissingPermission")
    fun start() {
        if (released || scanning || control != null) return
        val scanner = manager?.adapter?.bluetoothLeScanner
        if (scanner == null) {
            note(EntryKind.PROBLEM, "Bluetooth unavailable", "no LE scanner")
            return
        }
        scanning = true
        note(EntryKind.LINK, "Scanning", "looking for $DEVICE_NAME")
        // Filter on the service UUID and fall back to the advertised name in the
        // callback, because a controller that has just rebooted can be seen by name
        // before its service data lands.
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanner.startScan(listOf(filter), settings, scanCallback)
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        if (!scanning) return
        scanning = false
        runCatching { manager?.adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val record = result.scanRecord
            val matches = record?.serviceUuids?.any { it.uuid == SERVICE_UUID } == true ||
                record?.deviceName == DEVICE_NAME
            if (!matches || control != null || gatt != null) return
            stopScan()
            note(EntryKind.LINK, "Controller found", "rssi ${result.rssi} dBm")
            gatt = result.device.connectGatt(null, false, gattCallback, android.bluetooth.BluetoothDevice.TRANSPORT_LE)
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            note(EntryKind.PROBLEM, "Scan failed", "code $errorCode")
            handler.postDelayed({ start() }, RETRY_MS)
        }
    }

    @SuppressLint("MissingPermission")
    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                // MTU first, then discovery: the controller's notifications are short
                // records but the negotiated MTU decides whether a snapshot arrives in
                // one packet each.
                enqueue { gatt.requestMtu(185) }
            } else {
                dropped(gatt)
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            finishOperation()
            enqueue { gatt.discoverServices() }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            finishOperation()
            if (status != BluetoothGatt.GATT_SUCCESS) {
                note(EntryKind.PROBLEM, "Discovery failed", "status $status")
                dropped(gatt)
                return
            }
            val characteristic = gatt.getService(SERVICE_UUID)?.getCharacteristic(CONTROL_UUID)
            if (characteristic == null) {
                note(EntryKind.PROBLEM, "Control characteristic missing")
                dropped(gatt)
                return
            }
            control = characteristic
            gatt.setCharacteristicNotification(characteristic, true)
            val cccd = characteristic.getDescriptor(CCCD_UUID)
            if (cccd == null) {
                note(EntryKind.PROBLEM, "No CCCD", "notifications cannot be enabled")
            } else {
                enqueue { writeDescriptor(gatt, cccd) }
            }
            note(EntryKind.LINK, "Gateway linked", "7-inch controller over BLE")
            publish()
            requestSync()
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            finishOperation()
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                // A dropped command matters on a surface that drives relays.
                note(EntryKind.PROBLEM, "Command failed", "status $status")
            }
            finishOperation()
        }

        // Pre-33 delivers the value on the characteristic itself; 33+ passes it in.
        @Deprecated("Kept for API < 33")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            @Suppress("DEPRECATION")
            characteristic.value?.let { onLine(String(it).trim()) }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            onLine(String(value).trim())
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeDescriptor(gatt: BluetoothGatt, cccd: BluetoothGattDescriptor): Boolean {
        val enable = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(cccd, enable) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                cccd.value = enable
                gatt.writeDescriptor(cccd)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun dropped(gatt: BluetoothGatt?) {
        if (control != null) note(EntryKind.PROBLEM, "Gateway lost")
        control = null
        sequence = 0
        pathNodes["1"] = false
        pathNodes["2"] = false
        pending.clear()
        inFlight = false
        runCatching { gatt?.close() }
        this.gatt = null
        publish()
        if (!released) handler.postDelayed({ start() }, 400)
    }

    private fun onLine(line: String) {
        when {
            line.startsWith("!STATE:") -> {
                val fields = line.split(':')
                if (fields.size < 4) return
                val incoming = fields[1].toIntOrNull() ?: sequence
                // The controller bumps the sequence once per snapshot and notifies one
                // !STATE per bump, so a jump means a notification was dropped and the
                // nine !CHANNEL lines of that snapshot may have gone with it. A rewind
                // means it rebooted, which its self-heal watchdog now does on purpose.
                if (sequence != 0 && (incoming < sequence || incoming > sequence + 1)) {
                    if (incoming < sequence) {
                        note(EntryKind.LINK, "Gateway restarted", "sequence rewound to $incoming")
                    }
                    requestSync()
                }
                sequence = incoming
                mode = fields[2]
                ioNode = fields[3] == "ONLINE"
                if (channels.size >= 9) publish()
            }

            line.startsWith("!CHANNEL:") -> {
                val fields = line.split(':')
                if (fields.size < 3) return
                val id = fields[1]
                val health = fields[2]
                val previous = channels.put(id, health)
                if (previous != null && previous != health && id in Links.all) {
                    val faulted = health != "NORMAL"
                    note(
                        if (faulted) EntryKind.FAULT else EntryKind.RECOVERY,
                        if (faulted) "${Links.label(id)} isolated" else "${Links.label(id)} restored",
                        if (faulted) "relay open, pair carrying no traffic"
                        else "relay back in NC pass-through",
                    )
                }
            }

            line.startsWith("!PATHNODE:") -> {
                val fields = line.split(':')
                if (fields.size < 3) return
                val online = fields[2] == "ONLINE"
                val previous = pathNodes[fields[1]]
                pathNodes[fields[1]] = online
                if (previous != null && previous != online) {
                    note(
                        if (online) EntryKind.LINK else EntryKind.PROBLEM,
                        if (online) "Path ${fields[1]} node back" else "Path ${fields[1]} node lost",
                        if (online) "" else "controller will self-heal if it stays down",
                    )
                    publish()
                }
            }

            line.startsWith("!EVENT:") -> {
                val event = line.substring(7)
                if (event != "heartbeat") note(EntryKind.LINK, eventLabel(event), event)
                publish()
            }
        }
    }

    private fun eventLabel(event: String) = when (event) {
        "hello" -> "Gateway booted"
        "sync" -> "Snapshot synced"
        "recovered" -> "All paths recovered"
        "path_fault" -> "Path fault applied"
        "channel_changed" -> "Channel changed"
        "ble_connected" -> "Tablet attached"
        "ble_disconnected" -> "Tablet detached"
        else -> event
    }

    /** Rate limited, so a burst of dropped notifications cannot become a sync storm. */
    private fun requestSync() {
        val now = System.currentTimeMillis()
        if (now - lastSyncAt < SYNC_MIN_GAP_MS) return
        lastSyncAt = now
        write("!SYNC")
    }

    fun isolatePath(path: Int) {
        note(EntryKind.COMMAND, "Isolate path $path", "!PATH:$path")
        write("!PATH:$path")
    }

    fun recoverAll() {
        note(EntryKind.COMMAND, "Recover all paths", "!RECOVER")
        write("!RECOVER")
    }

    /**
     * A switch fault is not one command on this transport. `!SCENARIO:` is the
     * controller's *sensor* scenario space -- LiDAR loss, dual sensor, front TSN MRM,
     * and anything else means recover-all -- and the 4..6 switch numbering belongs to
     * the 7-inch's own touch actions. Sending `!SCENARIO:4` here quietly recovers
     * everything instead of isolating a switch, so the three links are commanded
     * explicitly. `!CHANNEL:` is not exclusive, which is why the untouched link is set
     * back to NORMAL rather than left as the previous action left it.
     */
    fun faultSwitch(label: String, links: Map<String, String>) {
        note(EntryKind.COMMAND, label, links.entries.joinToString(" ") { "${it.key}=${it.value}" })
        links.forEach { (channel, health) -> write("!CHANNEL:$channel:$health") }
    }

    @SuppressLint("MissingPermission")
    private fun write(command: String) {
        val characteristic = control
        val gatt = this.gatt
        if (characteristic == null || gatt == null) {
            note(EntryKind.PROBLEM, "Not sent", "$command: no gateway link")
            return
        }
        val payload = command.toByteArray()
        enqueue {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(
                    characteristic,
                    payload,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                ) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run {
                    characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    characteristic.value = payload
                    gatt.writeCharacteristic(characteristic)
                }
            }
        }
    }

    private fun enqueue(operation: () -> Boolean) {
        handler.post {
            pending.add(operation)
            pump()
        }
    }

    private fun finishOperation() {
        handler.post {
            inFlight = false
            pump()
        }
    }

    private fun pump() {
        if (inFlight) return
        val operation = pending.poll() ?: return
        inFlight = true
        val accepted = runCatching { operation() }.getOrDefault(false)
        if (!accepted) {
            // The stack refused it outright, so no callback is coming and holding the
            // slot would stall every later command.
            Log.w(TAG, "GATT operation refused")
            inFlight = false
            handler.post { pump() }
        }
    }

    @SuppressLint("MissingPermission")
    fun release() {
        released = true
        stopScan()
        handler.removeCallbacksAndMessages(null)
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        gatt = null
        control = null
    }
}
