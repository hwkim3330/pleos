import 'dart:async';

import 'package:flutter/material.dart';

import 'gateway_link.dart';
import 'link_state.dart';
import 'theme.dart';
import 'topology.dart';

class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final _link = GatewayLink();
  final _entries = <LogEntry>[];
  LinkState _state = const LinkState();
  String? _selected;
  StreamSubscription<LinkState>? _stateSub;
  StreamSubscription<LogEntry>? _logSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _link.states.listen((state) => setState(() => _state = state));
    _logSub = _link.log.listen((entry) {
      setState(() {
        _entries.insert(0, entry);
        // The timeline is for the last few minutes of a demo, not an audit trail,
        // and an unbounded list on a long-running console is a slow leak.
        if (_entries.length > 120) _entries.removeLast();
      });
    });
    _link.start();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _logSub?.cancel();
    _link.dispose();
    super.dispose();
  }

  void _run(_Action action) {
    setState(() => _selected = action.id);
    action.invoke(_link);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusBar(state: _state),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 272,
                      child: _ActionRail(
                        state: _state,
                        selected: _selected,
                        onRun: _run,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _Panel(
                        label: 'E/E TOPOLOGY',
                        trailing: _ModeBadge(state: _state),
                        child: TopologyView(state: _state),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 344,
                      child: _Panel(
                        label: 'EVENT TIMELINE',
                        trailing: Text('${_entries.length}', style: TypeScale.mono),
                        child: _Timeline(entries: _entries),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _NodeBar(state: _state),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled surface. Every panel on the screen uses this one container, so the
/// layout reads as a single system instead of a pile of differently-styled cards.
class _Panel extends StatelessWidget {
  const _Panel({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Tone.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tone.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(child: Text(label, style: TypeScale.label)),
                ?trailing,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final (word, colour, detail) = switch (state) {
      LinkState(gatewayOnline: false) => (
        'OFFLINE',
        Tone.idle,
        'searching for the 7-inch controller',
      ),
      LinkState(isFaulted: true) => (
        'ISOLATED',
        Tone.fault,
        '${state.faultedLinks.length} of 3 Ethernet paths open',
      ),
      _ => ('NOMINAL', Tone.healthy, 'three paths in NC pass-through'),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Tone.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tone.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            _Dot(colour: colour, size: 12),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(word, style: TypeScale.headline.copyWith(color: colour)),
                const SizedBox(height: 4),
                Text(detail, style: TypeScale.body),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('PLEOS RECONFIG HMI', style: TypeScale.label),
                const SizedBox(height: 6),
                Text(
                  'ZONAL FAULT INJECTION  ·  LAN9662 TSN RIG',
                  style: TypeScale.mono.copyWith(color: Tone.textFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.state});

  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final live = state.gatewayOnline;
    return Row(
      children: [
        Text('AUTOWARE', style: TypeScale.label),
        const SizedBox(width: 8),
        Text(
          live ? state.mode : '--',
          style: TypeScale.value.copyWith(
            color: live ? Tone.healthy : Tone.textFaint,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _Action {
  const _Action(this.id, this.title, this.subtitle, this.invoke);
  final String id;
  final String title;
  final String subtitle;
  final void Function(GatewayLink) invoke;
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.state,
    required this.selected,
    required this.onRun,
  });

  final LinkState state;
  final String? selected;
  final void Function(_Action) onRun;

  static final _pathFaults = [
    _Action('p1', 'Path 1 link down', 'Front A – Rear  ·  ESP-AR',
        (link) => link.isolatePath(1)),
    _Action('p2', 'Path 2 link down', 'Front B – Rear  ·  ESP-BR',
        (link) => link.isolatePath(2)),
    _Action('p3', 'Path 3 link down', 'Front A – Front B  ·  ESP-AB',
        (link) => link.isolatePath(3)),
  ];

  /// A switch fault isolates both links physically incident to that switch, which
  /// is the firmware's own definition (`setSwitchFault`). The third link is set
  /// back to NORMAL explicitly rather than left alone, so the result does not
  /// depend on whatever the previous action did.
  static final _switchFaults = [
    _Action('sa', 'Front A switch', 'isolates paths 1 and 3', (link) {
      link.faultSwitch('Front A switch fault', const {
        'tsn_front_a': 'FAULT',
        'tsn_rear': 'FAULT',
        'tsn_front_b': 'NORMAL',
      });
    }),
    _Action('sb', 'Front B switch', 'isolates paths 2 and 3', (link) {
      link.faultSwitch('Front B switch fault', const {
        'tsn_front_b': 'FAULT',
        'tsn_rear': 'FAULT',
        'tsn_front_a': 'NORMAL',
      });
    }),
    _Action('sr', 'Rear switch', 'isolates paths 1 and 2', (link) {
      link.faultSwitch('Rear switch fault', const {
        'tsn_front_a': 'FAULT',
        'tsn_front_b': 'FAULT',
        'tsn_rear': 'NORMAL',
      });
    }),
  ];

  @override
  Widget build(BuildContext context) {
    final enabled = state.gatewayOnline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Panel(
            label: 'INJECT',
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                const _RailHeading('LINK FAULT'),
                for (final action in _pathFaults)
                  _ActionTile(
                    action: action,
                    enabled: enabled,
                    active: selected == action.id,
                    onRun: onRun,
                  ),
                const SizedBox(height: 8),
                const _RailHeading('SWITCH FAULT'),
                for (final action in _switchFaults)
                  _ActionTile(
                    action: action,
                    enabled: enabled,
                    active: selected == action.id,
                    onRun: onRun,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _RecoverButton(
          enabled: enabled,
          onTap: () => onRun(
            _Action('recover', 'Recover all', '', (link) => link.recoverAll()),
          ),
        ),
      ],
    );
  }
}

class _RailHeading extends StatelessWidget {
  const _RailHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Text(text, style: TypeScale.label.copyWith(color: Tone.textFaint)),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.enabled,
    required this.active,
    required this.onRun,
  });

  final _Action action;
  final bool enabled;
  final bool active;
  final void Function(_Action) onRun;

  @override
  Widget build(BuildContext context) {
    final colour = active ? Tone.warning : Tone.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active ? Tone.warning.withValues(alpha: 0.10) : Tone.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? () => onRun(action) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.38,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.title,
                          style: TypeScale.value.copyWith(color: colour, fontSize: 14),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          action.subtitle,
                          style: TypeScale.mono.copyWith(color: Tone.textFaint),
                        ),
                      ],
                    ),
                  ),
                  if (active) _Dot(colour: Tone.warning, size: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recovery is the one action an operator needs to find without reading, so it is
/// the only filled control on the screen.
class _RecoverButton extends StatelessWidget {
  const _RecoverButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: Tone.healthy,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'RECOVER ALL PATHS',
                style: TextStyle(
                  fontSize: 14,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF04120C),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});

  final List<LogEntry> entries;

  static Color _colour(EntryKind kind) => switch (kind) {
    EntryKind.link => Tone.textSecondary,
    EntryKind.fault => Tone.fault,
    EntryKind.recovery => Tone.healthy,
    EntryKind.command => Tone.warning,
    EntryKind.problem => Tone.fault,
  };

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text('waiting for the gateway', style: TypeScale.mono),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 0, 14, 14),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final colour = _colour(entry.kind);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: _Dot(colour: colour, size: 7),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: TypeScale.value.copyWith(fontSize: 13, color: colour),
                          ),
                        ),
                        Text(entry.clock, style: TypeScale.mono.copyWith(color: Tone.textFaint)),
                      ],
                    ),
                    if (entry.detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(entry.detail, style: TypeScale.mono.copyWith(color: Tone.textFaint)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The row that answers "is the hardware actually there", which is the question
/// the older consoles could not answer: they showed a single last-event string, so
/// a node that dropped and came back left no trace.
class _NodeBar extends StatelessWidget {
  const _NodeBar({required this.state});

  final LinkState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          Expanded(
            child: _NodeTile(
              label: '7-INCH GATEWAY',
              value: state.gatewayOnline ? 'BLE CONTROL' : 'SEARCHING',
              detail: state.gatewayOnline ? 'snapshot #${state.sequence}' : 'no link',
              colour: state.gatewayOnline ? Tone.healthy : Tone.idle,
            ),
          ),
          const SizedBox(width: 12),
          for (final path in [1, 2, 3]) ...[
            Expanded(
              child: _NodeTile(
                label: path == 3 ? 'PATH 3  ·  LOCAL GPIO' : 'PATH $path  ·  ESP NODE',
                value: _nodeWord(path),
                detail: _relayWord(path),
                colour: _nodeColour(path),
              ),
            ),
            if (path != 3) const SizedBox(width: 12),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: _NodeTile(
              label: 'INLINE INJECTOR',
              value: state.ioNodeOnline ? 'ARMED' : 'SAFE BYPASS',
              detail: state.ioNodeOnline ? 'io node attached' : 'no USB io node',
              colour: state.ioNodeOnline ? Tone.warning : Tone.idle,
            ),
          ),
        ],
      ),
    );
  }

  String _nodeWord(int path) {
    if (!state.gatewayOnline) return '--';
    return state.pathNodeOnline(path) ? 'ACK' : 'LOST';
  }

  String _relayWord(int path) {
    if (!state.gatewayOnline) return 'no gateway link';
    final channel = LinkState.linkIds[path - 1];
    return state.linkHealthy(channel) ? 'relay NC pass-through' : 'relay open';
  }

  Color _nodeColour(int path) {
    if (!state.gatewayOnline) return Tone.idle;
    if (!state.pathNodeOnline(path)) return Tone.fault;
    return state.linkHealthy(LinkState.linkIds[path - 1]) ? Tone.healthy : Tone.fault;
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.colour,
  });

  final String label;
  final String value;
  final String detail;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Tone.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tone.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TypeScale.label),
            Row(
              children: [
                _Dot(colour: colour, size: 8),
                const SizedBox(width: 8),
                Text(value, style: TypeScale.value.copyWith(color: colour, fontSize: 16)),
              ],
            ),
            Text(detail, style: TypeScale.mono.copyWith(color: Tone.textFaint)),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.colour, required this.size});

  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: colour.withValues(alpha: 0.45), blurRadius: size),
        ],
      ),
    );
  }
}
