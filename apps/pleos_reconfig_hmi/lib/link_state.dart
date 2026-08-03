/// What the tablet knows about the rig, and nothing more. Every field here comes
/// off the wire from the 7-inch controller; there is no simulated or padded
/// value, because a console that mixes the two cannot be trusted during a fault.
class LinkState {
  const LinkState({
    this.gatewayOnline = false,
    this.mode = '--',
    this.sequence = 0,
    this.ioNodeOnline = false,
    this.channels = const {},
    this.pathNodesOnline = const {},
    this.lastEvent = '',
  });

  final bool gatewayOnline;
  final String mode;
  final int sequence;
  final bool ioNodeOnline;

  /// Channel id (`tsn_front_a`, `lidar_fl`, ...) to health word as reported.
  final Map<String, String> channels;

  /// `1` and `2` for the two physical path display nodes.
  final Map<String, bool> pathNodesOnline;

  final String lastEvent;

  bool get isFaulted => faultedLinks.isNotEmpty;

  /// The three Ethernet links, in the order the rig numbers them.
  static const linkIds = ['tsn_front_a', 'tsn_front_b', 'tsn_rear'];

  List<String> get faultedLinks =>
      linkIds.where((id) => (channels[id] ?? 'NORMAL') != 'NORMAL').toList();

  bool linkHealthy(String id) => (channels[id] ?? 'NORMAL') == 'NORMAL';

  /// Path 3 has no display node: the 7-inch drives that relay from its own GPIO,
  /// so its liveness is the gateway's own.
  bool pathNodeOnline(int path) =>
      path == 3 ? gatewayOnline : (pathNodesOnline['$path'] ?? false);

  LinkState copyWith({
    bool? gatewayOnline,
    String? mode,
    int? sequence,
    bool? ioNodeOnline,
    Map<String, String>? channels,
    Map<String, bool>? pathNodesOnline,
    String? lastEvent,
  }) {
    return LinkState(
      gatewayOnline: gatewayOnline ?? this.gatewayOnline,
      mode: mode ?? this.mode,
      sequence: sequence ?? this.sequence,
      ioNodeOnline: ioNodeOnline ?? this.ioNodeOnline,
      channels: channels ?? this.channels,
      pathNodesOnline: pathNodesOnline ?? this.pathNodesOnline,
      lastEvent: lastEvent ?? this.lastEvent,
    );
  }
}

enum EntryKind { link, fault, recovery, command, problem }

/// One line in the timeline. The older consoles showed a single "last event"
/// string, which is exactly the wrong shape for diagnosing a link that flaps:
/// you need the sequence of what happened and when.
class LogEntry {
  LogEntry(this.at, this.kind, this.title, [this.detail = '']);

  final DateTime at;
  final EntryKind kind;
  final String title;
  final String detail;

  String get clock =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';
}
