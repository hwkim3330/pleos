import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  Timer? _retry;
  bool _disposed = false;

  Stream<HardwareReconfigState> get states => _states.stream;

  void connect() => _open();

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
    await _socket?.close();
    await _states.close();
  }
}
