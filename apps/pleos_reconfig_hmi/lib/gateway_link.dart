import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'link_state.dart';

/// Direct BLE link to the 7-inch controller. The confirmed rig is tablet -> 7-inch
/// -> Path1/Path2, all BLE, with no host bridge anywhere in it, so this app owns
/// the GATT connection itself and has no websocket fallback to drift out of sync
/// with.
///
/// The connect sequence and its error handling are carried over from the studio
/// app rather than rewritten: each step in it exists because of a failure seen on
/// this hardware, and none of them are about how the screen looks.
class GatewayLink {
  GatewayLink();

  static const _deviceName = 'PLEOS-RECONFIG';
  static final _serviceUuid = Guid('7d2f0001-7c7a-4f7b-9b51-0af9a281d110');
  static final _controlUuid = Guid('7d2f0002-7c7a-4f7b-9b51-0af9a281d110');

  final _states = StreamController<LinkState>.broadcast();
  final _log = StreamController<LogEntry>.broadcast();

  Stream<LinkState> get states => _states.stream;
  Stream<LogEntry> get log => _log.stream;

  final Map<String, String> _channels = {};
  final Map<String, bool> _pathNodes = {'1': false, '2': false};
  String _mode = '--';
  int _sequence = 0;
  bool _ioNode = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _valueSub;
  Timer? _retry;
  DateTime? _lastSyncAt;
  bool _scanning = false;
  bool _connecting = false;
  bool _disposed = false;

  void _note(EntryKind kind, String title, [String detail = '']) {
    if (_disposed) return;
    _log.add(LogEntry(DateTime.now(), kind, title, detail));
  }

  LinkState get _snapshot => LinkState(
    gatewayOnline: _control != null,
    mode: _mode,
    sequence: _sequence,
    ioNodeOnline: _ioNode,
    channels: Map.unmodifiable(_channels),
    pathNodesOnline: Map.unmodifiable(_pathNodes),
  );

  void _publish() {
    if (!_disposed) _states.add(_snapshot);
  }

  Future<void> start() async {
    _note(EntryKind.link, 'Scanning', 'looking for $_deviceName');
    await _scan();
  }

  Future<void> _scan() async {
    if (_disposed || _scanning || _control != null) return;
    _scanning = true;
    try {
      if (!await FlutterBluePlus.isSupported) {
        _note(EntryKind.problem, 'No BLE adapter');
        return;
      }
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final advertised = result.advertisementData;
          if (advertised.serviceUuids.contains(_serviceUuid) ||
              advertised.advName == _deviceName) {
            FlutterBluePlus.stopScan();
            _connect(result.device);
            break;
          }
        }
      });
      // One long listening window, then retry almost immediately: a fixed sleep
      // between short scans meant a controller that rebooted just after a window
      // closed took over twenty seconds to be found, and every operator action in
      // that gap was lost.
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    } catch (error) {
      _note(EntryKind.problem, 'Scan failed', '$error');
    } finally {
      _scanning = false;
      if (!_disposed && _control == null && !_connecting) {
        _retry?.cancel();
        _retry = Timer(const Duration(milliseconds: 400), _scan);
      }
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_disposed || _control != null || _connecting) return;
    _connecting = true;
    _retry?.cancel();
    await FlutterBluePlus.stopScan();
    try {
      await device.connect(
        license: License.nonprofit,
        mtu: null,
        timeout: const Duration(seconds: 8),
      );
      _device = device;
      await device.requestMtu(185);
      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) _dropped();
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final services = await device.discoverServices(timeout: 12);
      final service = services.firstWhere((item) => item.uuid == _serviceUuid);
      final control = service.characteristics.firstWhere(
        (item) => item.uuid == _controlUuid,
      );
      _control = control;
      await _valueSub?.cancel();
      _valueSub = control.lastValueStream.listen(_onValue);
      await control.setNotifyValue(true);
      await _requestSync();
      _note(EntryKind.link, 'Gateway linked', '7-inch controller over BLE');
      _publish();
    } catch (error) {
      // disconnect() throws in its own right when the adapter went away, and
      // letting that escape used to skip the teardown below: no timer, no scan,
      // no subscription, so the link stayed dead until the app was restarted.
      try {
        await device.disconnect();
      } catch (_) {
        // Already gone; the retry the teardown schedules is what matters.
      }
      _note(EntryKind.problem, 'Connect failed', '$error');
      _dropped();
    } finally {
      _connecting = false;
    }
  }

  void _dropped() {
    if (_control != null) _note(EntryKind.problem, 'Gateway lost');
    _control = null;
    _device = null;
    _sequence = 0;
    _pathNodes['1'] = false;
    _pathNodes['2'] = false;
    _publish();
    if (_disposed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 400), _scan);
  }

  void _onValue(List<int> value) {
    final line = utf8.decode(value, allowMalformed: true).trim();
    if (line.startsWith('!STATE:')) {
      final fields = line.split(':');
      if (fields.length < 4) return;
      final sequence = int.tryParse(fields[1]) ?? _sequence;
      // The controller bumps the sequence once per snapshot and notifies one
      // !STATE per bump, so a jump means a notification was dropped and the nine
      // !CHANNEL lines of that snapshot may have gone with it. A decrease means it
      // rebooted -- which the self-heal watchdog now does deliberately. Either way
      // the cached channel map cannot be trusted, so ask for a fresh one.
      if (_sequence != 0 &&
          (sequence < _sequence || sequence > _sequence + 1)) {
        if (sequence < _sequence) {
          _note(EntryKind.link, 'Gateway restarted', 'sequence rewound to $sequence');
        }
        _requestSync().ignore();
      }
      _sequence = sequence;
      _mode = fields[2];
      _ioNode = fields[3] == 'ONLINE';
      if (_channels.length >= 9) _publish();
      return;
    }
    if (line.startsWith('!CHANNEL:')) {
      final fields = line.split(':');
      if (fields.length < 3) return;
      final id = fields[1];
      final health = fields[2];
      final previous = _channels[id];
      _channels[id] = health;
      if (previous != null && previous != health && LinkState.linkIds.contains(id)) {
        final faulted = health != 'NORMAL';
        _note(
          faulted ? EntryKind.fault : EntryKind.recovery,
          faulted ? '${_linkLabel(id)} isolated' : '${_linkLabel(id)} restored',
          faulted ? 'relay open, pair carrying no traffic' : 'relay back in NC pass-through',
        );
      }
      return;
    }
    if (line.startsWith('!PATHNODE:')) {
      final fields = line.split(':');
      if (fields.length < 3) return;
      final online = fields[2] == 'ONLINE';
      final previous = _pathNodes[fields[1]];
      _pathNodes[fields[1]] = online;
      if (previous != null && previous != online) {
        _note(
          online ? EntryKind.link : EntryKind.problem,
          online ? 'Path ${fields[1]} node back' : 'Path ${fields[1]} node lost',
          online ? '' : 'controller will self-heal if it stays down',
        );
        _publish();
      }
      return;
    }
    if (line.startsWith('!EVENT:')) {
      final event = line.substring(7);
      if (event != 'heartbeat') _note(EntryKind.link, _eventLabel(event), event);
      _publish();
    }
  }

  static String _linkLabel(String id) => switch (id) {
    'tsn_front_a' => 'Path 1',
    'tsn_front_b' => 'Path 2',
    'tsn_rear' => 'Path 3',
    _ => id,
  };

  static String _eventLabel(String event) => switch (event) {
    'hello' => 'Gateway booted',
    'sync' => 'Snapshot synced',
    'recovered' => 'All paths recovered',
    'path_fault' => 'Path fault applied',
    'channel_changed' => 'Channel changed',
    'ble_connected' => 'Tablet attached',
    'ble_disconnected' => 'Tablet detached',
    _ => event,
  };

  /// Rate limited, so a burst of dropped notifications cannot become a sync storm.
  Future<void> _requestSync() async {
    final control = _control;
    if (control == null) return;
    final now = DateTime.now();
    final last = _lastSyncAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastSyncAt = now;
    await control.write(utf8.encode('!SYNC'), withoutResponse: false);
  }

  void isolatePath(int path) => _write('!PATH:$path', 'Isolate path $path');

  /// A switch fault is not one command on this transport. `!SCENARIO:` is the
  /// controller's *sensor* scenario space (LiDAR loss, dual-sensor, front TSN MRM,
  /// and anything else means recover-all), and the 4..6 switch numbering belongs to
  /// the 7-inch's own touch actions, not to BLE. Sending `!SCENARIO:4` here quietly
  /// recovered everything instead of isolating a switch. So the three links are
  /// commanded explicitly, which is also what makes the intent readable on the wire.
  Future<void> faultSwitch(String label, Map<String, String> links) async {
    final control = _control;
    if (control == null) {
      _note(EntryKind.problem, 'Not sent', '$label: no gateway link');
      return;
    }
    _note(EntryKind.command, label, links.entries.map((e) => '${e.key}=${e.value}').join(' '));
    for (final entry in links.entries) {
      // Sequential and awaited: `!CHANNEL:` is not exclusive, so a dropped write
      // would leave a link in whatever state the previous action left it.
      try {
        await control.write(
          utf8.encode('!CHANNEL:${entry.key}:${entry.value}'),
          withoutResponse: false,
        );
      } catch (error) {
        _note(EntryKind.problem, 'Command failed', '${entry.key}: $error');
        return;
      }
    }
  }

  void recoverAll() => _write('!RECOVER', 'Recover all paths');

  void _write(String command, String description) {
    final control = _control;
    if (control == null) {
      _note(EntryKind.problem, 'Not sent', '$description: no gateway link');
      return;
    }
    _note(EntryKind.command, description, command);
    // A dropped command matters on a surface that drives relays, so the failure
    // is surfaced instead of vanishing into an unawaited future.
    control.write(utf8.encode(command), withoutResponse: false).catchError((
      Object error,
    ) {
      _note(EntryKind.problem, 'Command failed', '$command: $error');
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await _connectionSub?.cancel();
    await _valueSub?.cancel();
    await _device?.disconnect();
    await _states.close();
    await _log.close();
  }
}
