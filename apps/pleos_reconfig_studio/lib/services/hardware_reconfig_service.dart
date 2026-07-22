import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class HardwareReconfigState {
  const HardwareReconfigState({
    this.connected = false,
    this.mode = 'OFFLINE',
    this.event = 'Waiting for ESP controller',
    this.channels = const {},
    this.sequence = 0,
    this.ioNodeConnected = false,
  });

  final bool connected;
  final String mode;
  final String event;
  final Map<String, String> channels;
  final int sequence;
  final bool ioNodeConnected;
}

class HardwareReconfigService {
  HardwareReconfigService({this.url = 'ws://10.0.2.2:8766'});

  final String url;
  final _states = StreamController<HardwareReconfigState>.broadcast();
  WebSocket? _socket;
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _bleControl;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  Timer? _retry;
  Timer? _bleRetry;
  bool _disposed = false;
  bool _bleConnecting = false;
  final Map<String, String> _bleChannels = {};
  String _bleMode = 'UNKNOWN';
  int _bleSequence = 0;
  bool _bleIoNodeConnected = false;

  static final Guid _bleServiceUuid = Guid(
    '7d2f0001-7c7a-4f7b-9b51-0af9a281d110',
  );
  static final Guid _bleControlUuid = Guid(
    '7d2f0002-7c7a-4f7b-9b51-0af9a281d110',
  );

  Stream<HardwareReconfigState> get states => _states.stream;

  void connect() {
    _open();
    _startBleScan();
  }

  Future<void> _startBleScan() async {
    if (_disposed || _bleConnecting || _bleControl != null) return;
    _bleConnecting = true;
    try {
      if (!await FlutterBluePlus.isSupported) return;
      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          if (result.advertisementData.serviceUuids.contains(_bleServiceUuid) ||
              result.advertisementData.advName == 'PLEOS-RECONFIG') {
            FlutterBluePlus.stopScan();
            _connectBle(result.device);
            break;
          }
        }
      });
      await FlutterBluePlus.startScan(
        withServices: [_bleServiceUuid],
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // Android Automotive emulators commonly expose no BLE adapter.
    } finally {
      _bleConnecting = false;
      if (!_disposed && _bleControl == null) {
        _bleRetry?.cancel();
        _bleRetry = Timer(const Duration(seconds: 3), _startBleScan);
      }
    }
  }

  Future<void> _connectBle(BluetoothDevice device) async {
    if (_disposed || _bleControl != null) return;
    try {
      await device.connect(
        license: License.nonprofit,
        mtu: null,
        timeout: const Duration(seconds: 8),
      );
      _bleDevice = device;
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) _bleDisconnected();
      });
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (item) => item.uuid == _bleServiceUuid,
      );
      final control = service.characteristics.firstWhere(
        (item) => item.uuid == _bleControlUuid,
      );
      _bleControl = control;
      await _valueSubscription?.cancel();
      _valueSubscription = control.lastValueStream.listen(_onBleValue);
      await control.setNotifyValue(true);
      await control.write(utf8.encode('!SYNC'), withoutResponse: false);
    } catch (_) {
      await device.disconnect();
      _bleDisconnected();
    }
  }

  void _onBleValue(List<int> value) {
    final line = utf8.decode(value, allowMalformed: true).trim();
    var emit = false;
    if (line.startsWith('!STATE:')) {
      final fields = line.split(':');
      if (fields.length >= 4) {
        _bleSequence = int.tryParse(fields[1]) ?? _bleSequence;
        _bleMode = fields[2];
        _bleIoNodeConnected = fields[3] == 'ONLINE';
        emit = _bleChannels.length >= 9;
      }
    } else if (line.startsWith('!CHANNEL:')) {
      final fields = line.split(':');
      if (fields.length >= 3) _bleChannels[fields[1]] = fields[2];
    } else if (line.startsWith('!EVENT:')) {
      emit = true;
    }
    if (!emit) return;
    _states.add(
      HardwareReconfigState(
        connected: true,
        mode: _bleMode,
        event: line.startsWith('!EVENT:') ? line.substring(7) : 'BLE linked',
        channels: Map.unmodifiable(_bleChannels),
        sequence: _bleSequence,
        ioNodeConnected: _bleIoNodeConnected,
      ),
    );
  }

  void _bleDisconnected() {
    _bleControl = null;
    _bleDevice = null;
    if (!_disposed) {
      _bleRetry?.cancel();
      _bleRetry = Timer(const Duration(seconds: 2), _startBleScan);
    }
  }

  Future<void> _open() async {
    if (_disposed || _socket != null) return;
    try {
      final socket = await WebSocket.connect(
        url,
      ).timeout(const Duration(seconds: 2));
      if (_disposed) return socket.close();
      _socket = socket;
      socket.listen(
        _onMessage,
        onDone: _disconnected,
        onError: (_) => _disconnected(),
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      if (data.containsKey('error')) return;
      final channels = (data['channels'] as Map? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
      _states.add(
        HardwareReconfigState(
          connected: true,
          mode: data['mode']?.toString() ?? 'UNKNOWN',
          event: data['event']?.toString() ?? 'state',
          channels: channels,
          sequence: (data['seq'] as num?)?.toInt() ?? 0,
          ioNodeConnected: data['io_node_connected'] == true,
        ),
      );
    } catch (_) {
      // The host bridge validates framing and CRC. Ignore malformed JSON only.
    }
  }

  void runScenario(int scenario) =>
      _send({'command': 'scenario', 'id': scenario});

  void setChannel(String id, String health) =>
      _send({'command': 'channel', 'id': id, 'health': health});

  void recover() => _send({'command': 'recover'});

  void _send(Map<String, Object> command) {
    final control = _bleControl;
    if (control != null) {
      final String wireCommand;
      if (command['command'] == 'recover') {
        wireCommand = '!RECOVER';
      } else if (command['command'] == 'scenario') {
        wireCommand = '!SCENARIO:${command['id']}';
      } else {
        wireCommand = '!CHANNEL:${command['id']}:${command['health']}';
      }
      control.write(utf8.encode(wireCommand), withoutResponse: false);
      return;
    }
    _socket?.add(jsonEncode(command));
  }

  void _disconnected() {
    _socket = null;
    if (!_disposed) {
      _states.add(const HardwareReconfigState());
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), _open);
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    _bleRetry?.cancel();
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _valueSubscription?.cancel();
    await _bleDevice?.disconnect();
    await _socket?.close();
    await _states.close();
  }
}
