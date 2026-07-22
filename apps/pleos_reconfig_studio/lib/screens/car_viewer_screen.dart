import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../core/js_scripts.dart';
import '../models/fault_data.dart';
import '../providers/fault_provider.dart';
import '../providers/hardware_reconfig_provider.dart';
import '../services/hardware_reconfig_service.dart';
import '../providers/viewer_service_provider.dart';

class CarViewerScreen extends ConsumerStatefulWidget {
  const CarViewerScreen({super.key});

  @override
  ConsumerState<CarViewerScreen> createState() => _CarViewerScreenState();
}

class _CarViewerScreenState extends ConsumerState<CarViewerScreen> {
  var _labelsVisible = true;
  var _topologyVisible = false;
  var _metricsVisible = true;
  _ScenarioDef _selectedScenario = _ScenarioDef.values.first;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(faultProvider));
  }

  Future<void> _waitForJsAndInitialize() async {
    final service = ref.read(viewerServiceProvider);
    for (var i = 0; i < 24; i++) {
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      if (await service.isJsReady()) {
        await service.initializeLabelHotspots();
        await service.toggleHotspots(_labelsVisible);
        return;
      }
    }
    await service.initializeLabelHotspots();
    await service.toggleHotspots(_labelsVisible);
  }

  void _applyScenario(_ScenarioDef scenario) {
    setState(() => _selectedScenario = scenario);
    ref.read(faultProvider.notifier).applyScenario(scenario.id);
  }

  void _recover() {
    ref.read(faultProvider.notifier).clearAll();
    ref.read(viewerServiceProvider).resetCameraOrbit();
    setState(() => _selectedScenario = _ScenarioDef.values.first);
  }

  void _toggleLabels() {
    setState(() => _labelsVisible = !_labelsVisible);
    ref.read(viewerServiceProvider).toggleHotspots(_labelsVisible);
  }

  @override
  Widget build(BuildContext context) {
    final faults = ref.watch(faultProvider).values.toList();
    final hardware =
        ref.watch(hardwareReconfigProvider).valueOrNull ??
        const HardwareReconfigState();
    final mode = hardware.connected
        ? _ReconfigMode.fromHardware(hardware.mode, faults)
        : _ReconfigMode.fromScenario(_selectedScenario, faults);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFFF6F8FB)),
          ModelViewer(
            backgroundColor: const Color(0xFFF6F8FB),
            id: 'car',
            src: 'lib/assets/roii_reconfig.glb',
            alt: 'PLEOS reconfigurable E/E architecture vehicle',
            interpolationDecay: 200,
            disablePan: true,
            disableTap: true,
            disableZoom: false,
            cameraControls: true,
            autoRotate: false,
            cameraOrbit: '45deg 65deg 100%',
            cameraTarget: 'auto 8m auto',
            relatedJs: modelViewerScript,
            onWebViewCreated: (controller) {
              ref.read(viewerServiceProvider).setController(controller);
              _waitForJsAndInitialize();
            },
          ),
          if (_topologyVisible)
            const Positioned.fill(
              child: IgnorePointer(child: _TopologyOverlay()),
            ),
          Positioned(
            left: 14,
            right: 14,
            top: 10,
            child: _TopBar(
              mode: mode,
              scenario: _selectedScenario,
              hardware: hardware,
            ),
          ),
          Positioned(
            left: 14,
            top: 78,
            bottom: 118,
            child: _ScenarioRail(
              selected: _selectedScenario,
              onSelected: _applyScenario,
            ),
          ),
          Positioned(
            right: 14,
            top: 78,
            bottom: 118,
            child: _EvidencePanel(
              scenario: _selectedScenario,
              mode: mode,
              faults: faults,
            ),
          ),
          Positioned(
            left: 248,
            right: 348,
            bottom: 118,
            child: _ModeCard(
              mode: mode,
              scenario: _selectedScenario,
              hardware: hardware,
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: _BottomConsole(
              labelsVisible: _labelsVisible,
              topologyVisible: _topologyVisible,
              metricsVisible: _metricsVisible,
              mode: mode,
              onToggleLabels: _toggleLabels,
              onToggleTopology: () =>
                  setState(() => _topologyVisible = !_topologyVisible),
              onToggleMetrics: () =>
                  setState(() => _metricsVisible = !_metricsVisible),
              onToggleShell: () =>
                  ref.read(viewerServiceProvider).toggleMaterials(),
              onRecover: _recover,
            ),
          ),
          if (_metricsVisible)
            Positioned(
              left: 248,
              right: 348,
              bottom: 72,
              child: _TimelinePanel(scenario: _selectedScenario, mode: mode),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.scenario,
    required this.hardware,
  });

  final _ReconfigMode mode;
  final _ScenarioDef scenario;
  final HardwareReconfigState hardware;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(
              Icons.account_tree_rounded,
              color: Color(0xFF155EEF),
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'PLEOS Reconfig Studio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 14),
            _StatusPill(
              label: 'Controller',
              value: hardware.connected
                  ? 'ESP #${hardware.sequence}'
                  : 'Offline',
              color: hardware.connected
                  ? const Color(0xFF0F766E)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            _StatusPill(
              label: 'Inline injector',
              value: hardware.ioNodeConnected ? 'USB armed' : 'Safe bypass',
              color: hardware.ioNodeConnected
                  ? const Color(0xFF0F766E)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            _StatusPill(
              label: 'Path nodes',
              value:
                  '${hardware.pathNodes.values.where((online) => online).length}/2 online',
              color:
                  hardware.pathNodes.values.where((online) => online).length ==
                      2
                  ? const Color(0xFF0F766E)
                  : const Color(0xFFD97706),
            ),
            const SizedBox(width: 8),
            _StatusPill(
              label: 'Scenario',
              value: scenario.title,
              color: scenario.color,
            ),
            const SizedBox(width: 8),
            _StatusPill(label: 'Autoware', value: mode.name, color: mode.color),
            const SizedBox(width: 8),
            _StatusPill(
              label: 'Safety goal',
              value: scenario.safetyGoal,
              color: mode.color,
            ),
            const SizedBox(width: 8),
            const _StatusPill(
              label: 'Network',
              value: 'TSN/FRER',
              color: Color(0xFF155EEF),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioRail extends StatelessWidget {
  const _ScenarioRail({required this.selected, required this.onSelected});

  final _ScenarioDef selected;
  final ValueChanged<_ScenarioDef> onSelected;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      width: 220,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Test Sequences',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Inject  ·  Isolate  ·  Reconfigure  ·  Recover',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: _ScenarioDef.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final scenario = _ScenarioDef.values[index];
                final active = scenario == selected;
                return Material(
                  color: active
                      ? scenario.color.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => onSelected(scenario),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active
                              ? scenario.color
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(scenario.icon, size: 19, color: scenario.color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  scenario.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  scenario.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.scenario,
    required this.mode,
    required this.faults,
  });

  final _ScenarioDef scenario;
  final _ReconfigMode mode;
  final List<FaultData> faults;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      width: 318,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evidence / Validation',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          _EvidenceBlock(
            title: 'Fault chain',
            lines: [scenario.cause, scenario.effect],
          ),
          _EvidenceBlock(
            title: 'Reconfiguration',
            lines: [
              scenario.action,
              'Mode: ${mode.name}',
              'MRM: ${scenario.mrmPolicy}',
            ],
          ),
          _EvidenceBlock(title: 'Validation metrics', lines: scenario.metrics),
          _EvidenceBlock(
            title: 'Report mapping',
            lines: scenario.reportMapping,
          ),
          const SizedBox(height: 6),
          const Text(
            'Active faults',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: faults.isEmpty
                ? const Center(
                    child: Text(
                      'No active fault\nTriple sensor baseline',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: faults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final fault = faults[index];
                      final color = fault.severity >= 2
                          ? const Color(0xFFDC2626)
                          : const Color(0xFFF59E0B);
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withValues(alpha: 0.32),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fault.target,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fault.faultType,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.scenario,
    required this.hardware,
  });

  final _ReconfigMode mode;
  final _ScenarioDef scenario;
  final HardwareReconfigState hardware;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: _Glass(
        width: 430,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'INLINE RECONFIGURATION PATH',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                _PathPair(
                  fromLabel: 'F-A',
                  espLabel: 'ESP-AB',
                  toLabel: 'F-B',
                  armed: hardware.ioNodeConnected,
                ),
                const SizedBox(height: 4),
                _PathPair(
                  fromLabel: 'F-A',
                  espLabel: 'ESP-AR',
                  toLabel: 'R',
                  armed: hardware.ioNodeConnected,
                ),
                const SizedBox(height: 4),
                _PathPair(
                  fromLabel: 'F-B',
                  espLabel: 'ESP-BR',
                  toLabel: 'R',
                  armed: hardware.ioNodeConnected,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(mode.icon, color: mode.color, size: 22),
                const SizedBox(width: 8),
                Text(
                  mode.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: mode.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            _ModeLine(
              label: 'Localization',
              value: mode.localization,
              color: mode.color,
            ),
            _ModeLine(
              label: 'Fusion',
              value: scenario.fusion,
              color: mode.color,
            ),
            _ModeLine(
              label: 'Planning',
              value: mode.planning,
              color: mode.color,
            ),
            _ModeLine(label: 'Control', value: mode.control, color: mode.color),
          ],
        ),
      ),
    );
  }
}

class _PathNode extends StatelessWidget {
  const _PathNode({
    required this.label,
    required this.active,
    this.warning = false,
  });

  final String label;
  final bool active;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? const Color(0xFFD97706)
        : active
        ? const Color(0xFF0F766E)
        : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _PathPair extends StatelessWidget {
  const _PathPair({
    required this.fromLabel,
    required this.espLabel,
    required this.toLabel,
    required this.armed,
  });

  final String fromLabel;
  final String espLabel;
  final String toLabel;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PathNode(label: fromLabel, active: true),
        const Expanded(child: Divider(height: 1)),
        _PathNode(label: espLabel, active: armed, warning: !armed),
        const Expanded(child: Divider(height: 1)),
        _PathNode(label: toLabel, active: true),
      ],
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.scenario, required this.mode});

  final _ScenarioDef scenario;
  final _ReconfigMode mode;

  @override
  Widget build(BuildContext context) {
    final steps = scenario.id == 'triple'
        ? ['Normal', 'Monitor', 'Validate']
        : [
            'Inject',
            'Detect',
            'Reconfig',
            'Switch',
            'Validate',
            mode.isMrm ? 'MRM' : 'Recover',
          ];
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              _TimelineStep(
                label: steps[i],
                active: true,
                color: i >= 2 ? mode.color : scenario.color,
              ),
              if (i != steps.length - 1)
                Container(
                  width: 22,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: const Color(0xFFCBD5E1),
                ),
            ],
            const SizedBox(width: 14),
            _MetricChip(
              label: 'switch',
              value: scenario.switchTime,
              color: mode.color,
            ),
            const SizedBox(width: 6),
            _MetricChip(
              label: 'latency',
              value: scenario.latency,
              color: mode.color,
            ),
            const SizedBox(width: 6),
            _MetricChip(
              label: 'jitter',
              value: scenario.jitter,
              color: mode.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomConsole extends StatelessWidget {
  const _BottomConsole({
    required this.labelsVisible,
    required this.topologyVisible,
    required this.metricsVisible,
    required this.mode,
    required this.onToggleLabels,
    required this.onToggleTopology,
    required this.onToggleMetrics,
    required this.onToggleShell,
    required this.onRecover,
  });

  final bool labelsVisible;
  final bool topologyVisible;
  final bool metricsVisible;
  final _ReconfigMode mode;
  final VoidCallback onToggleLabels;
  final VoidCallback onToggleTopology;
  final VoidCallback onToggleMetrics;
  final VoidCallback onToggleShell;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _Glass(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ToolButton(
              icon: Icons.label_rounded,
              label: labelsVisible ? 'Hide Labels' : 'Show Labels',
              active: labelsVisible,
              onTap: onToggleLabels,
            ),
            _ToolButton(
              icon: Icons.account_tree_rounded,
              label: topologyVisible ? 'Hide Topology' : 'Show Topology',
              active: topologyVisible,
              onTap: onToggleTopology,
            ),
            _ToolButton(
              icon: Icons.timeline_rounded,
              label: metricsVisible ? 'Hide Metrics' : 'Show Metrics',
              active: metricsVisible,
              onTap: onToggleMetrics,
            ),
            _ToolButton(
              icon: Icons.layers_rounded,
              label: 'Vehicle shell',
              onTap: onToggleShell,
            ),
            _ToolButton(
              icon: Icons.verified_user_rounded,
              label: mode.isMrm ? 'MRM validate' : 'Recover validate',
              active: mode.isFaulted,
              onTap: onRecover,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopologyOverlay extends StatelessWidget {
  const _TopologyOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TopologyPainter());
  }
}

class _TopologyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.50);
    final nodes = {
      'ZG-FL': Offset(size.width * 0.43, size.height * 0.58),
      'ZG-FR': Offset(size.width * 0.58, size.height * 0.58),
      'ZG-R': Offset(size.width * 0.54, size.height * 0.39),
      'ADS': Offset(size.width * 0.50, size.height * 0.48),
      'VCU': Offset(size.width * 0.45, size.height * 0.42),
    };
    final linkPaint = Paint()
      ..color = const Color(0xFF155EEF).withValues(alpha: 0.26)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final fallbackPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.36)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(nodes['ZG-FL']!, nodes['ADS']!, linkPaint);
    canvas.drawLine(nodes['ZG-FR']!, nodes['ADS']!, linkPaint);
    canvas.drawLine(nodes['ZG-R']!, nodes['ADS']!, linkPaint);
    canvas.drawLine(nodes['ADS']!, nodes['VCU']!, fallbackPaint);
    canvas.drawCircle(center, 2, Paint()..color = Colors.transparent);
    for (final entry in nodes.entries) {
      final rect = Rect.fromCenter(
        center: entry.value,
        width: entry.key == 'ADS' ? 58 : 54,
        height: 26,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(
        rrect,
        Paint()..color = Colors.white.withValues(alpha: 0.78),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFF155EEF).withValues(alpha: 0.48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, entry.value - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EvidenceBlock extends StatelessWidget {
  const _EvidenceBlock({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeLine extends StatelessWidget {
  const _ModeLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.active,
    required this.color,
  });

  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : const Color(0xFFE2E8F0),
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF155EEF) : const Color(0xFF334155);
    return Material(
      color: active ? const Color(0xFFEFF6FF) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.width,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ScenarioDef {
  const _ScenarioDef({
    required this.id,
    required this.category,
    required this.title,
    required this.icon,
    required this.color,
    required this.cause,
    required this.effect,
    required this.action,
    required this.modeName,
    required this.fusion,
    required this.safetyGoal,
    required this.mrmPolicy,
    required this.metrics,
    required this.reportMapping,
    required this.switchTime,
    required this.latency,
    required this.jitter,
  });

  final String id;
  final String category;
  final String title;
  final IconData icon;
  final Color color;
  final String cause;
  final String effect;
  final String action;
  final String modeName;
  final String fusion;
  final String safetyGoal;
  final String mrmPolicy;
  final List<String> metrics;
  final List<String> reportMapping;
  final String switchTime;
  final String latency;
  final String jitter;

  static const values = [
    _ScenarioDef(
      id: 'triple',
      category: 'Baseline',
      title: 'Triple sensor normal',
      icon: Icons.verified_rounded,
      color: Color(0xFF16A34A),
      cause: 'No active electrical component fault.',
      effect: 'LiDAR/GNSS/Camera all available.',
      action: 'Keep nominal E/E topology and Autoware full stack.',
      modeName: 'Triple sensor',
      fusion: 'LiDAR 0.4 / GNSS 0.3 / Camera 0.3',
      safetyGoal: 'Full DDT',
      mrmPolicy: 'standby',
      metrics: [
        'Localization confidence normal',
        'No topology degradation',
        'Recovery validation armed',
      ],
      reportMapping: ['인지범위별 삼중 센서 측위 모드', 'Lv.4 플랫폼 정상 주행 기준'],
      switchTime: '0ms',
      latency: '1ms',
      jitter: '0.5ms',
    ),
    _ScenarioDef(
      id: 'gnssDrift',
      category: 'Sensor Fault',
      title: 'GNSS drift',
      icon: Icons.satellite_alt_rounded,
      color: Color(0xFFF59E0B),
      cause: 'GNSS 좌표가 오도미터 이동거리와 불일치.',
      effect: '절대 측위 신뢰도 저하, map position jump 위험.',
      action: 'GNSS fusion weight를 0으로 낮추고 LiDAR + Camera 측위로 전환.',
      modeName: 'LiDAR + Camera',
      fusion: 'LiDAR 0.6 / GNSS 0.0 / Camera 0.4',
      safetyGoal: 'No position jump',
      mrmPolicy: 'standby',
      metrics: [
        'Mode switch time measured',
        'Localization discontinuity check',
        'Odometer cross-check passed',
      ],
      reportMapping: ['GNSS 오류 판정: 오도미터 이동거리 불일치', '이중 센서에서 단일/대체 측위 전환 영향 분석'],
      switchTime: '82ms',
      latency: '1ms',
      jitter: '0.5ms',
    ),
    _ScenarioDef(
      id: 'lidarFrontCenter',
      category: 'Sensor Fault',
      title: 'LiDAR-FC unavailable',
      icon: Icons.radar_rounded,
      color: Color(0xFFEF4444),
      cause: '전방 중앙 LiDAR 데이터 상실.',
      effect: '전방 point cloud coverage 감소.',
      action: '좌/우 LiDAR와 GNSS/Camera로 partial fusion 재구성.',
      modeName: 'LiDAR partial fusion',
      fusion: 'LiDAR side pair 0.5 / GNSS 0.2 / Camera 0.3',
      safetyGoal: 'Maintain DDT degraded',
      mrmPolicy: 'standby',
      metrics: [
        'Point-cloud confidence down',
        'Speed cap validated',
        'No center-lane discontinuity',
      ],
      reportMapping: ['4개 라이다 기반 Lv.4 차량 플랫폼', '센서 고장 시 다른 센서 데이터로 시스템 조정'],
      switchTime: '96ms',
      latency: '1ms',
      jitter: '0.6ms',
    ),
    _ScenarioDef(
      id: 'cameraLost',
      category: 'Sensor Fault',
      title: 'Camera unavailable',
      icon: Icons.videocam_off_rounded,
      color: Color(0xFFF59E0B),
      cause: '전방 카메라 신뢰도 상실.',
      effect: '차선/visual odometry 신뢰도 저하.',
      action: 'LiDAR NDT + GNSS 측위 기반 stack으로 전환.',
      modeName: 'LiDAR + GNSS',
      fusion: 'LiDAR 0.7 / GNSS 0.3 / Camera 0.0',
      safetyGoal: 'Lane-safe degraded',
      mrmPolicy: 'standby',
      metrics: [
        'Lane feature unavailable',
        'NDT localization stable',
        'Speed cap 45km/h',
      ],
      reportMapping: ['이중 센서 주행 모드', 'Autoware 측위/탐지/계획/제어 pipeline'],
      switchTime: '74ms',
      latency: '1ms',
      jitter: '0.5ms',
    ),
    _ScenarioDef(
      id: 'gnssOnly',
      category: 'Sensor Fault',
      title: 'GNSS only degraded',
      icon: Icons.public_rounded,
      color: Color(0xFFDC2626),
      cause: 'LiDAR와 Camera가 동시에 제한됨.',
      effect: '자율주행 지속 가능성 낮음, MRM 후보.',
      action: 'GNSS hold로 위치를 유지하고 차선 변경/고속 제어 차단.',
      modeName: 'GNSS only',
      fusion: 'LiDAR 0.0 / GNSS 1.0 / Camera 0.0',
      safetyGoal: 'Minimal risk ready',
      mrmPolicy: 'candidate',
      metrics: [
        'Control authority reduced',
        'No lane change',
        'MRM trigger monitored',
      ],
      reportMapping: ['단일 센서 주행 모드', '복구 불가능 결함 발생 시 단계적 저하'],
      switchTime: '118ms',
      latency: '1.4ms',
      jitter: '0.8ms',
    ),
    _ScenarioDef(
      id: 'tsnSyncLost',
      category: 'Network Fault',
      title: 'TSN time sync lost',
      icon: Icons.sync_problem_rounded,
      color: Color(0xFFEF4444),
      cause: 'Front Zonal Gateway PTP/GM 동기 상실.',
      effect: '센서 timestamp alignment 실패 위험.',
      action: 'BMCA failover와 FRER redundant path를 활성화.',
      modeName: 'TSN reconfigured',
      fusion: 'Sensor fusion held until time base validated',
      safetyGoal: 'Bounded latency',
      mrmPolicy: 'standby',
      metrics: [
        'PTP failover check',
        'FRER path continuity',
        'DetNet jitter threshold',
      ],
      reportMapping: ['TSN FRER 및 DetNet 지연시간 편차 보장', 'Zonal Gateway 오류검지 기능'],
      switchTime: '64ms',
      latency: '1ms',
      jitter: '0.5ms',
    ),
    _ScenarioDef(
      id: 'frerPathLost',
      category: 'Network Fault',
      title: 'FRER path A lost',
      icon: Icons.cable_rounded,
      color: Color(0xFFF59E0B),
      cause: '전방 Ethernet path A 단절.',
      effect: '중복 경로 중 하나가 손실되지만 센서 수집은 유지 가능.',
      action: 'Path B를 active로 유지하고 hitless recovery를 검증.',
      modeName: 'FRER fail-operational',
      fusion: 'Fusion unchanged, network path reweighted',
      safetyGoal: 'No packet loss impact',
      mrmPolicy: 'standby',
      metrics: [
        'Hitless switchover',
        'Latency max under limit',
        'No Autoware mode drop',
      ],
      reportMapping: [
        'Frame Replication and Elimination for Reliability',
        'Automotive Ethernet 기반 통합 네트워크',
      ],
      switchTime: '34ms',
      latency: '1ms',
      jitter: '0.5ms',
    ),
    _ScenarioDef(
      id: 'zgFrontIsolated',
      category: 'Zonal Gateway Fault',
      title: 'ZG-F isolated',
      icon: Icons.hub_rounded,
      color: Color(0xFFEF4444),
      cause: '전방 Zonal Gateway 통신 고립.',
      effect: '전방 센서 수집 경로와 ADS compute 입력이 제한됨.',
      action: '백업 gateway 경로로 센서 데이터를 우회하고 confidence를 낮춤.',
      modeName: 'Zonal degraded',
      fusion: 'Front sensors down-weighted, rear/side context held',
      safetyGoal: 'Fail-operational',
      mrmPolicy: 'standby/candidate',
      metrics: [
        'Gateway isolation detected',
        'Backup route active',
        'Safety goal check',
      ],
      reportMapping: ['Zonal 아키텍처 적용 요구사항', '데이터 수집 및 고장 진단/대응 구조'],
      switchTime: '126ms',
      latency: '1.6ms',
      jitter: '0.9ms',
    ),
    _ScenarioDef(
      id: 'localizationDelayed',
      category: 'Autoware Fault',
      title: 'Localization delayed',
      icon: Icons.memory_rounded,
      color: Color(0xFFF59E0B),
      cause: 'Autoware localization callback 지연 증가.',
      effect: '측위 pipeline tail latency 증가.',
      action: '자원 스케줄링과 watchdog으로 localization node를 안정화.',
      modeName: 'Pipeline scheduled',
      fusion: 'Fusion unchanged, compute resource reallocated',
      safetyGoal: 'Bounded callback',
      mrmPolicy: 'standby',
      metrics: [
        'Callback period checked',
        'Resource schedule applied',
        'Mode transition not required',
      ],
      reportMapping: ['Autoware pipeline 성능 영향 분석', '자원 스케줄링 기술 개발'],
      switchTime: '48ms',
      latency: '1.2ms',
      jitter: '0.7ms',
    ),
    _ScenarioDef(
      id: 'compoundRain',
      category: 'Compound Fault',
      title: 'Rain/fog confidence drop',
      icon: Icons.thunderstorm_rounded,
      color: Color(0xFFDC2626),
      cause: '우천/안개/야간 환경에서 LiDAR와 Camera 신뢰도가 동시에 감소.',
      effect: '인지범위 축소, planning confidence 감소.',
      action: 'GNSS/odometry 비중을 높이고 속도 제한, 필요 시 MRM으로 전환.',
      modeName: 'Compound degraded',
      fusion: 'LiDAR 0.2 / GNSS 0.5 / Camera 0.3',
      safetyGoal: 'Controlled degradation',
      mrmPolicy: 'candidate',
      metrics: [
        'Perception confidence threshold',
        'Planning route confidence',
        'Speed cap 25km/h',
      ],
      reportMapping: ['SOTIF 관점 원인 시나리오', '복합 결함 기반 시뮬레이터 검증'],
      switchTime: '142ms',
      latency: '1.8ms',
      jitter: '1.0ms',
    ),
    _ScenarioDef(
      id: 'mrmStop',
      category: 'MRM Required',
      title: 'MRM safe stop',
      icon: Icons.emergency_rounded,
      color: Color(0xFFDC2626),
      cause: '센서 조합으로 Autoware 주행 stack 유지 불가.',
      effect: '정상 또는 저하 주행 지속 불가.',
      action: 'MRM behavior로 안전 정지 trajectory를 실행.',
      modeName: 'MRM safe stop',
      fusion: 'Fusion disabled after stop target fixed',
      safetyGoal: 'Minimal risk condition',
      mrmPolicy: 'active',
      metrics: ['Stop trajectory active', 'Hazard signal', 'Remote telemetry'],
      reportMapping: ['결함/오류 시나리오 기반 실차 검증', '안전성 향상 기능 재구성'],
      switchTime: '210ms',
      latency: '2ms',
      jitter: '1.2ms',
    ),
  ];
}

class _ReconfigMode {
  const _ReconfigMode({
    required this.name,
    required this.localization,
    required this.planning,
    required this.control,
    required this.color,
    required this.icon,
    required this.isFaulted,
    required this.isMrm,
  });

  final String name;
  final String localization;
  final String planning;
  final String control;
  final Color color;
  final IconData icon;
  final bool isFaulted;
  final bool isMrm;

  factory _ReconfigMode.fromScenario(
    _ScenarioDef scenario,
    List<FaultData> faults,
  ) {
    if (scenario.id == 'triple' && faults.isEmpty) {
      return const _ReconfigMode(
        name: 'Triple sensor',
        localization: 'LiDAR + GNSS + Camera',
        planning: 'Normal route',
        control: 'Normal MPC control',
        color: Color(0xFF16A34A),
        icon: Icons.verified_rounded,
        isFaulted: false,
        isMrm: false,
      );
    }
    final mrm = scenario.id == 'mrmStop';
    return _ReconfigMode(
      name: scenario.modeName,
      localization: scenario.fusion,
      planning: mrm ? 'Safe stop trajectory' : 'Constraint-aware route',
      control: mrm ? 'Controlled stop' : 'Confidence-based cap',
      color: scenario.color,
      icon: mrm ? Icons.emergency_rounded : Icons.change_circle_rounded,
      isFaulted: true,
      isMrm: mrm,
    );
  }

  factory _ReconfigMode.fromHardware(String mode, List<FaultData> faults) {
    if (mode == 'MRM') {
      return const _ReconfigMode(
        name: 'MRM safe stop',
        localization: 'Dead reckoning to stop target',
        planning: 'Safe stop trajectory',
        control: 'Controlled stop + hazards',
        color: Color(0xFFDC2626),
        icon: Icons.emergency_rounded,
        isFaulted: true,
        isMrm: true,
      );
    }
    final normalized = switch (mode) {
      'TRIPLE' => 'Triple sensor',
      'DUAL' => 'Dual sensor',
      'SINGLE' => 'Single sensor',
      _ => mode,
    };
    final color = mode == 'TRIPLE'
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    return _ReconfigMode(
      name: normalized,
      localization: '$normalized confirmed by ESP controller',
      planning: mode == 'TRIPLE' ? 'Normal route' : 'Constraint-aware route',
      control: mode == 'TRIPLE' ? 'Normal MPC control' : 'Confidence-based cap',
      color: color,
      icon: mode == 'TRIPLE'
          ? Icons.verified_rounded
          : Icons.change_circle_rounded,
      isFaulted: faults.isNotEmpty,
      isMrm: false,
    );
  }
}
