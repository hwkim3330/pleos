package com.keti.pleos.reconfig3d

import android.Manifest
import android.os.Build
import android.os.Bundle
import android.view.TextureView

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material3.Text
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native operator console: Filament renders the vehicle and Compose draws the HMI over
 * it. Same GATT contract and same visual language as the Flutter HMI, but the 3D model is
 * the subject here rather than a schematic, and the link state is painted onto the model
 * itself.
 */
class MainActivity : ComponentActivity() {

    private lateinit var gateway: BleGateway
    private var renderer: VehicleRenderer? = null

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            // Start regardless of the answer: the gateway reports its own failure into the
            // timeline, which is more useful than a blank screen with no explanation.
            gateway.start()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        gateway = BleGateway(this)

        setContent {
            val state by gateway.state.collectAsStateWithLifecycle()
            val entries = remember { mutableStateListOf<LogEntry>() }
            androidx.compose.runtime.LaunchedEffect(Unit) {
                gateway.log.collect { entry ->
                    entries.add(0, entry)
                    // The timeline covers the last few minutes of a demo, not an audit
                    // trail; unbounded growth on a console that runs all day is a leak.
                    if (entries.size > 120) entries.removeAt(entries.lastIndex)
                }
            }
            renderer?.apply(state)
            Console(
                state = state,
                entries = entries,
                onSurface = { view ->
                    renderer = VehicleRenderer(this, view).also { it.resume() }
                },
                onAction = { it.invoke(gateway) },
                onToggleShell = { visible -> renderer?.setShellVisible(visible) },
            )
        }

        requestPermissions()
    }

    private fun requestPermissions() {
        val needed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        permissionLauncher.launch(needed)
    }

    override fun onResume() {
        super.onResume()
        renderer?.resume()
    }

    override fun onPause() {
        renderer?.pause()
        super.onPause()
    }

    override fun onDestroy() {
        renderer?.destroy()
        gateway.release()
        super.onDestroy()
    }
}

private class Action(
    val title: String,
    val subtitle: String,
    val invoke: (BleGateway) -> Unit,
)

private val pathFaults = listOf(
    Action("Path 1 link down", "Front A – Rear  ·  ESP-AR") { it.isolatePath(1) },
    Action("Path 2 link down", "Front B – Rear  ·  ESP-BR") { it.isolatePath(2) },
    Action("Path 3 link down", "Front A – Front B  ·  ESP-AB") { it.isolatePath(3) },
)

/**
 * A switch fault isolates both links physically incident to that switch, matching the
 * firmware's `setSwitchFault`. The third link is set back to NORMAL explicitly, because
 * `!CHANNEL:` is not exclusive and the result would otherwise depend on the last action.
 */
private val switchFaults = listOf(
    Action("Front A switch", "isolates paths 1 and 3") { gateway ->
        gateway.faultSwitch(
            "Front A switch fault",
            linkedMapOf(
                Links.PATH1 to "FAULT",
                Links.PATH3 to "FAULT",
                Links.PATH2 to "NORMAL",
            ),
        )
    },
    Action("Front B switch", "isolates paths 2 and 3") { gateway ->
        gateway.faultSwitch(
            "Front B switch fault",
            linkedMapOf(
                Links.PATH2 to "FAULT",
                Links.PATH3 to "FAULT",
                Links.PATH1 to "NORMAL",
            ),
        )
    },
    Action("Rear switch", "isolates paths 1 and 2") { gateway ->
        gateway.faultSwitch(
            "Rear switch fault",
            linkedMapOf(
                Links.PATH1 to "FAULT",
                Links.PATH2 to "FAULT",
                Links.PATH3 to "NORMAL",
            ),
        )
    },
)

@Composable
private fun Console(
    state: LinkState,
    entries: List<LogEntry>,
    onSurface: (TextureView) -> Unit,
    onAction: (Action) -> Unit,
    onToggleShell: (Boolean) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Tone.background)
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        StatusBar(state)
        Row(
            modifier = Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(
                modifier = Modifier.width(272.dp).fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Panel(
                    label = "INJECT",
                    modifier = Modifier.weight(1f),
                ) {
                    LazyColumn(contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) {
                        item { RailHeading("LINK FAULT") }
                        items(pathFaults) { ActionTile(it, state.gatewayOnline, onAction) }
                        item { Spacer(Modifier.height(8.dp)) }
                        item { RailHeading("SWITCH FAULT") }
                        items(switchFaults) { ActionTile(it, state.gatewayOnline, onAction) }
                    }
                }
                RecoverButton(state.gatewayOnline) { onAction(Action("", "") { it.recoverAll() }) }
            }
            Panel(
                label = "ROII VEHICLE  ·  LIVE LINK PAINT",
                modifier = Modifier.weight(1f),
                trailing = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        ShellToggle(onToggleShell)
                        Spacer(Modifier.width(16.dp))
                        ModeBadge(state)
                    }
                },
            ) {
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { context ->
                        TextureView(context).also(onSurface)
                    },
                )
            }
            Panel(
                label = "EVENT TIMELINE",
                modifier = Modifier.width(344.dp),
                trailing = { Text("${entries.size}", style = Face.mono) },
            ) {
                Timeline(entries)
            }
        }
        NodeBar(state)
    }
}

@Composable
private fun Panel(
    label: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxHeight()
            .background(Tone.surface, RoundedCornerShape(16.dp))
            .border(1.dp, Tone.hairline, RoundedCornerShape(16.dp)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 18.dp, end = 18.dp, top = 16.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = Face.label, modifier = Modifier.weight(1f))
            trailing?.invoke()
        }
        Box(modifier = Modifier.weight(1f)) { content() }
    }
}

@Composable
private fun StatusBar(state: LinkState) {
    val (word, colour, detail) = when {
        !state.gatewayOnline ->
            Triple("OFFLINE", Tone.idle, "searching for the 7-inch controller")
        state.isFaulted -> Triple(
            "ISOLATED",
            Tone.fault,
            "${state.faultedLinks.size} of 3 Ethernet paths open",
        )
        else -> Triple("NOMINAL", Tone.healthy, "three paths in NC pass-through")
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tone.surface, RoundedCornerShape(16.dp))
            .border(1.dp, Tone.hairline, RoundedCornerShape(16.dp))
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Dot(colour, 12.dp)
        Spacer(Modifier.width(14.dp))
        Column {
            Text(word, style = Face.headline.copy(color = colour))
            Spacer(Modifier.height(4.dp))
            Text(detail, style = Face.body)
        }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text("PLEOS RECONFIG 3D", style = Face.label)
            Spacer(Modifier.height(6.dp))
            Text(
                "NATIVE FILAMENT  ·  LAN9662 TSN RIG",
                style = Face.mono.copy(color = Tone.textFaint),
            )
        }
    }
}

/**
 * The shell starts hidden: the body is opaque, and with it on screen none of the parts
 * this console paints are visible at all.
 */
@Composable
private fun ShellToggle(onToggle: (Boolean) -> Unit) {
    var visible by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    Row(
        modifier = Modifier
            .background(Tone.surfaceRaised, RoundedCornerShape(8.dp))
            .clickable {
                visible = !visible
                onToggle(visible)
            }
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Dot(if (visible) Tone.warning else Tone.idle, 7.dp)
        Spacer(Modifier.width(8.dp))
        Text("BODY SHELL", style = Face.label.copy(color = Tone.textSecondary))
    }
}

@Composable
private fun ModeBadge(state: LinkState) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("AUTOWARE", style = Face.label)
        Spacer(Modifier.width(8.dp))
        Text(
            if (state.gatewayOnline) state.mode else "--",
            style = Face.value.copy(
                color = if (state.gatewayOnline) Tone.healthy else Tone.textFaint,
                fontSize = 13.sp,
            ),
        )
    }
}

@Composable
private fun RailHeading(text: String) {
    Text(
        text,
        style = Face.label,
        modifier = Modifier.padding(horizontal = 6.dp, vertical = 8.dp),
    )
}

@Composable
private fun ActionTile(action: Action, enabled: Boolean, onAction: (Action) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 6.dp)
            .background(Tone.surfaceRaised, RoundedCornerShape(10.dp))
            .clickable(enabled = enabled) { onAction(action) }
            .padding(start = 14.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
    ) {
        Text(
            action.title,
            style = Face.value.copy(
                fontSize = 14.sp,
                color = if (enabled) Tone.textPrimary else Tone.textFaint,
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(3.dp))
        Text(action.subtitle, style = Face.mono.copy(color = Tone.textFaint))
    }
}

/** Recovery is the one control an operator must find without reading, so it is the only filled one. */
@Composable
private fun RecoverButton(enabled: Boolean, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (enabled) Tone.healthy else Tone.healthy.copy(alpha = 0.35f),
                RoundedCornerShape(14.dp),
            )
            .clickable(enabled = enabled) { onTap() }
            .padding(vertical = 20.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "RECOVER ALL PATHS",
            style = Face.value.copy(
                color = Color(0xFF04120C),
                letterSpacing = 1.2.sp,
                fontSize = 14.sp,
            ),
        )
    }
}

private val clock = SimpleDateFormat("HH:mm:ss", Locale.US)

@Composable
private fun Timeline(entries: List<LogEntry>) {
    if (entries.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("waiting for the gateway", style = Face.mono)
        }
        return
    }
    LazyColumn(contentPadding = PaddingValues(start = 18.dp, end = 14.dp, bottom = 14.dp)) {
        items(entries) { entry ->
            val colour = when (entry.kind) {
                EntryKind.LINK -> Tone.textSecondary
                EntryKind.FAULT -> Tone.fault
                EntryKind.RECOVERY -> Tone.healthy
                EntryKind.COMMAND -> Tone.warning
                EntryKind.PROBLEM -> Tone.fault
            }
            Row(modifier = Modifier.padding(bottom = 12.dp)) {
                Box(Modifier.padding(top = 5.dp)) { Dot(colour, 7.dp) }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Row {
                        Text(
                            entry.title,
                            style = Face.value.copy(fontSize = 13.sp, color = colour),
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            clock.format(Date(entry.atMillis)),
                            style = Face.mono.copy(color = Tone.textFaint),
                        )
                    }
                    if (entry.detail.isNotEmpty()) {
                        Spacer(Modifier.height(2.dp))
                        Text(entry.detail, style = Face.mono.copy(color = Tone.textFaint))
                    }
                }
            }
        }
    }
}

/** Answers "is the hardware actually there", which a last-event string cannot. */
@Composable
private fun NodeBar(state: LinkState) {
    Row(
        modifier = Modifier.fillMaxWidth().height(96.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        NodeTile(
            modifier = Modifier.weight(1f),
            label = "7-INCH GATEWAY",
            value = if (state.gatewayOnline) "BLE CONTROL" else "SEARCHING",
            detail = if (state.gatewayOnline) "snapshot #${state.sequence}" else "no link",
            colour = if (state.gatewayOnline) Tone.healthy else Tone.idle,
        )
        for (path in 1..3) {
            NodeTile(
                modifier = Modifier.weight(1f),
                label = if (path == 3) "PATH 3  ·  LOCAL GPIO" else "PATH $path  ·  ESP NODE",
                value = when {
                    !state.gatewayOnline -> "--"
                    state.pathNodeOnline(path) -> "ACK"
                    else -> "LOST"
                },
                detail = when {
                    !state.gatewayOnline -> "no gateway link"
                    state.linkHealthy(Links.all[path - 1]) -> "relay NC pass-through"
                    else -> "relay open"
                },
                colour = when {
                    !state.gatewayOnline -> Tone.idle
                    !state.pathNodeOnline(path) -> Tone.fault
                    state.linkHealthy(Links.all[path - 1]) -> Tone.healthy
                    else -> Tone.fault
                },
            )
        }
        NodeTile(
            modifier = Modifier.weight(1f),
            label = "INLINE INJECTOR",
            value = if (state.ioNodeOnline) "ARMED" else "SAFE BYPASS",
            detail = if (state.ioNodeOnline) "io node attached" else "no USB io node",
            colour = if (state.ioNodeOnline) Tone.warning else Tone.idle,
        )
    }
}

@Composable
private fun NodeTile(
    modifier: Modifier,
    label: String,
    value: String,
    detail: String,
    colour: Color,
) {
    Column(
        modifier = modifier
            .fillMaxHeight()
            .background(Tone.surface, RoundedCornerShape(14.dp))
            .border(1.dp, Tone.hairline, RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = Face.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Dot(colour, 8.dp)
            Spacer(Modifier.width(8.dp))
            Text(value, style = Face.value.copy(color = colour, fontSize = 16.sp))
        }
        Text(detail, style = Face.mono.copy(color = Tone.textFaint), maxLines = 1)
    }
}

@Composable
private fun Dot(colour: Color, size: androidx.compose.ui.unit.Dp) {
    Box(Modifier.size(size).background(colour, CircleShape))
}
