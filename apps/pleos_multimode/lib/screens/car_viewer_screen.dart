import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../core/js_scripts.dart';
import '../models/fault_data.dart';
import '../providers/fault_provider.dart';
import '../providers/viewer_service_provider.dart';
import 'widgets/fault_bottom_sheet.dart';

class CarViewerScreen extends ConsumerStatefulWidget {
  const CarViewerScreen({super.key});

  @override
  ConsumerState<CarViewerScreen> createState() => _CarViewerScreenState();
}

class _CarViewerScreenState extends ConsumerState<CarViewerScreen> {
  bool _labelsVisible = false;
  bool _faultSheetVisible = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(faultProvider));
    Future.delayed(const Duration(seconds: 2), _startFaultHotspotPolling);
  }

  void _startFaultHotspotPolling() {
    if (!mounted) return;
    _checkFaultHotspotClicked();
    Future.delayed(const Duration(milliseconds: 500), _startFaultHotspotPolling);
  }

  Future<void> _checkFaultHotspotClicked() async {
    final service = ref.read(viewerServiceProvider);
    final targetId = await service.checkErrorHotspotClicked();
    if (targetId == null || !mounted) return;
    final faults = ref.read(faultProvider.notifier).getFaultsByTarget(targetId);
    if (faults.isNotEmpty) _showFaultBottomSheet(faults);
  }

  void _showFaultBottomSheet(List<FaultData> faults) {
    setState(() => _faultSheetVisible = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      isScrollControlled: true,
      constraints: const BoxConstraints(minWidth: double.infinity, maxWidth: double.infinity),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: FaultBottomSheet(faults: faults),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() => _faultSheetVisible = false);
      ref.read(viewerServiceProvider).resetCameraOrbit();
    });
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

  void _toggleLabels() {
    setState(() => _labelsVisible = !_labelsVisible);
    ref.read(viewerServiceProvider).toggleHotspots(_labelsVisible);
  }

  void _applyScenario(_Scenario scenario) {
    ref.read(faultProvider.notifier).applyScenario(scenario.id);
  }

  @override
  Widget build(BuildContext context) {
    final faults = ref.watch(faultProvider);
    final assessment = _Assessment.fromFaults(faults.values);
    final mode = _AutowareMode.fromFaults(faults.values);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ModelViewer(
            backgroundColor: const Color(0xFFF8FAFC),
            id: 'car',
            src: 'lib/assets/roii.glb',
            alt: 'PLEOS Autoware multimode 3D vehicle',
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
          Positioned(
            left: 14,
            top: 10,
            right: 14,
            child: _TopRail(mode: mode),
          ),
          Positioned(
            left: 16,
            top: 86,
            child: AnimatedOpacity(
              opacity: _faultSheetVisible ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: _MrmBadge(assessment: assessment, mode: mode),
            ),
          ),
          Positioned(
            right: 16,
            top: 86,
            bottom: 104,
            child: _ScenarioRail(
              selectedColor: assessment.color,
              onScenario: _applyScenario,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: _BottomRail(
              labelsVisible: _labelsVisible,
              mode: mode,
              onToggleLabels: _toggleLabels,
              onToggleShell: () => ref.read(viewerServiceProvider).toggleMaterials(),
              onRecover: () {
                ref.read(faultProvider.notifier).clearAll();
                ref.read(viewerServiceProvider).resetCameraOrbit();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopRail extends StatelessWidget {
  const _TopRail({required this.mode});

  final _AutowareMode mode;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.directions_car_rounded, color: Color(0xFF155EEF), size: 20),
          const SizedBox(width: 9),
          const Text(
            'PLEOS Multimode',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Autoware stack: ${mode.name}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mode.color),
            ),
          ),
          const Text(
            'TSN switches: FL / FR / R',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _MrmBadge extends StatelessWidget {
  const _MrmBadge({required this.assessment, required this.mode});

  final _Assessment assessment;
  final _AutowareMode mode;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      width: 208,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(assessment.icon, color: assessment.color, size: 30),
          const SizedBox(height: 8),
          Text(
            assessment.label,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: assessment.color),
          ),
          const SizedBox(height: 5),
          Text(
            assessment.action,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 12),
          for (final step in assessment.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 15, color: assessment.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      step,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 16),
          _ModeLine(label: 'Mode', value: mode.name, color: mode.color),
          _ModeLine(label: 'Localization', value: mode.localization, color: mode.color),
          _ModeLine(label: 'Planning', value: mode.planning, color: mode.color),
          _ModeLine(label: 'Control', value: mode.control, color: mode.color),
          const Divider(height: 16),
          const _RecoveryFlow(),
        ],
      ),
    );
  }
}

class _ScenarioRail extends StatelessWidget {
  const _ScenarioRail({required this.selectedColor, required this.onScenario});

  final Color selectedColor;
  final ValueChanged<_Scenario> onScenario;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      width: 268,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Autoware Multimode Control',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: _Scenario.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final scenario = _Scenario.values[index];
                return _ScenarioButton(
                  scenario: scenario,
                  accent: scenario.color == Colors.transparent ? selectedColor : scenario.color,
                  onTap: () => onScenario(scenario),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioButton extends StatelessWidget {
  const _ScenarioButton({required this.scenario, required this.accent, required this.onTap});

  final _Scenario scenario;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF).withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.36)),
          ),
          child: Row(
            children: [
              Icon(scenario.icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scenario.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scenario.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomRail extends StatelessWidget {
  const _BottomRail({
    required this.labelsVisible,
    required this.mode,
    required this.onToggleLabels,
    required this.onToggleShell,
    required this.onRecover,
  });

  final bool labelsVisible;
  final _AutowareMode mode;
  final VoidCallback onToggleLabels;
  final VoidCallback onToggleShell;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _Glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Wrap(
          spacing: 6,
          runSpacing: 7,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ToolButton(icon: Icons.label_rounded, label: labelsVisible ? 'Hide Labels' : 'Show Labels', active: labelsVisible, onTap: onToggleLabels),
            _ToolButton(icon: Icons.layers_rounded, label: 'Vehicle shell', onTap: onToggleShell),
            _ToolButton(icon: Icons.settings_backup_restore_rounded, label: 'Recover stack', active: mode.isRecoveryTarget, onTap: onRecover),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF155EEF) : const Color(0xFF334155);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: label,
        child: FilledButton.tonalIcon(
          onPressed: onTap,
          icon: Icon(icon, size: 17, color: color),
          label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: active ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          ),
        ),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.padding, this.width});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Assessment {
  const _Assessment({
    required this.label,
    required this.action,
    required this.signal,
    required this.steps,
    required this.color,
    required this.icon,
  });

  final String label;
  final String action;
  final String signal;
  final List<String> steps;
  final Color color;
  final IconData icon;

  static _Assessment fromFaults(Iterable<FaultData> faults) {
    final list = faults.toList();
    final critical = list.where((fault) => fault.severity >= 2).length;
    if (critical >= 2 || list.length >= 3) {
      return const _Assessment(
      label: 'MRM ACTIVE',
        action: 'Autoware 주행 stack 유지 불가, 최소위험기동 실행',
        signal: 'Autoware MRM behavior',
        steps: ['Fallback behavior', 'Hazard signal', 'Safe stop trajectory'],
        color: Color(0xFFDC2626),
        icon: Icons.report_rounded,
      );
    }
    if (list.isNotEmpty) {
      return const _Assessment(
        label: 'MULTI MODE',
        action: '사용 가능한 센서 조합으로 Autoware stack 전환',
        signal: 'Stack reconfiguration',
        steps: ['Sensor availability', 'Stack switch', 'Control limit'],
        color: Color(0xFFD97706),
        icon: Icons.warning_rounded,
      );
    }
    return const _Assessment(
      label: 'TRIPLE MODE',
      action: 'LiDAR/GNSS/Camera 삼중 센서 기반 정상 운용',
      signal: 'LiDAR + GNSS + Camera',
      steps: ['NDT localization', 'Lane-camera check', 'Normal control'],
      color: Color(0xFF16A34A),
      icon: Icons.verified_rounded,
    );
  }
}

class _Scenario {
  const _Scenario({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  static const values = [
    _Scenario(id: 'triple', label: 'Triple sensor mode', description: 'LiDAR + GNSS + Camera 정상 Autoware stack', icon: Icons.hub_rounded, color: Color(0xFF16A34A)),
    _Scenario(id: 'cameraLost', label: 'LiDAR + GNSS mode', description: 'Camera 상실, NDT + GNSS 기반 주행', icon: Icons.videocam_off_rounded, color: Color(0xFFF59E0B)),
    _Scenario(id: 'gnssDenied', label: 'LiDAR + Camera mode', description: 'GNSS 음영, LiDAR odometry + 차선 인식', icon: Icons.satellite_alt_rounded, color: Color(0xFFF59E0B)),
    _Scenario(id: 'lidarDegraded', label: 'GNSS + Camera mode', description: 'LiDAR 성능 저하, GNSS + visual lane 저속 운용', icon: Icons.blur_off_rounded, color: Color(0xFFF59E0B)),
    _Scenario(id: 'lidarFrontLeft', label: 'LiDAR-FL degraded', description: '좌전방 LiDAR 저하, 좌측 차선 변경 제한', icon: Icons.radar_rounded, color: Color(0xFFF59E0B)),
    _Scenario(id: 'lidarFrontCenter', label: 'LiDAR-FC unavailable', description: '중앙 LiDAR 상실, 좌/우 LiDAR로 재구성', icon: Icons.radar_rounded, color: Color(0xFFEF4444)),
    _Scenario(id: 'lidarFrontRight', label: 'LiDAR-FR degraded', description: '우전방 LiDAR 저하, 우측 차선 변경 제한', icon: Icons.radar_rounded, color: Color(0xFFF59E0B)),
    _Scenario(id: 'lidarRearCenter', label: 'LiDAR-RC degraded', description: '후방 LiDAR 저하, 후측방 confidence 감소', icon: Icons.radar_rounded, color: Color(0xFFF59E0B)),
    _Scenario(id: 'singleLidar', label: 'LiDAR only mode', description: 'Camera/GNSS 제한, LiDAR 단일 기반 crawl', icon: Icons.radar_rounded, color: Color(0xFFEF4444)),
    _Scenario(id: 'cameraOnly', label: 'Camera only mode', description: 'LiDAR/GNSS 제한, 차선 유지 전용 저속 운용', icon: Icons.videocam_rounded, color: Color(0xFFEF4444)),
    _Scenario(id: 'mrmStop', label: 'MRM safe stop', description: 'Autoware 주행 stack 유지 불가, 안전 정지', icon: Icons.emergency_rounded, color: Color(0xFFDC2626)),
  ];
}

class _ModeLine extends StatelessWidget {
  const _ModeLine({required this.label, required this.value, required this.color});

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
            width: 74,
            child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: color)),
          ),
        ],
      ),
    );
  }
}

class _RecoveryFlow extends StatelessWidget {
  const _RecoveryFlow();

  @override
  Widget build(BuildContext context) {
    const steps = ['Detect', 'Switch', 'Validate', 'Recover'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recovery',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 7),
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                const Icon(Icons.check_rounded, size: 13, color: Color(0xFF155EEF)),
                const SizedBox(width: 6),
                Text(
                  step,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF334155)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AutowareMode {
  const _AutowareMode({
    required this.name,
    required this.localization,
    required this.planning,
    required this.control,
    required this.color,
  });

  final String name;
  final String localization;
  final String planning;
  final String control;
  final Color color;

  bool get isRecoveryTarget => name != 'Triple sensor';

  static _AutowareMode fromFaults(Iterable<FaultData> faults) {
    final targets = faults.map((fault) => fault.target).toSet();
    final hasCamera = targets.any((target) => target.contains('Camera'));
    final hasLidar = targets.any((target) => target.contains('Lidar'));
    final lidarFaultCount = targets.where((target) => target.contains('Lidar')).length;
    final hasGnss = targets.contains('TCU');
    final critical = faults.where((fault) => fault.severity >= 2).length;

    if (critical >= 3) {
      return const _AutowareMode(
        name: 'MRM safe stop',
        localization: 'Dead reckoning hold',
        planning: 'MRM behavior path',
        control: 'Safe stop trajectory',
        color: Color(0xFFDC2626),
      );
    }
    if (hasCamera && hasGnss && hasLidar) {
      return const _AutowareMode(
        name: 'LiDAR only crawl',
        localization: 'LiDAR NDT only',
        planning: 'Nearest safe lane',
        control: 'Crawl + MRM standby',
        color: Color(0xFFEF4444),
      );
    }
    if (hasCamera && hasGnss) {
      return const _AutowareMode(
        name: 'LiDAR only crawl',
        localization: 'LiDAR NDT only',
        planning: 'Nearest safe lane',
        control: 'Crawl + MRM standby',
        color: Color(0xFFEF4444),
      );
    }
    if (hasCamera && hasLidar) {
      return const _AutowareMode(
        name: 'GNSS only limited',
        localization: 'GNSS + IMU hold',
        planning: 'Map route confidence down',
        control: '20 km/h cap',
        color: Color(0xFFEF4444),
      );
    }
    if (hasLidar && hasGnss) {
      return const _AutowareMode(
        name: 'Camera only limited',
        localization: 'Visual lane tracking',
        planning: 'Lane keep only',
        control: '15 km/h cap',
        color: Color(0xFFEF4444),
      );
    }
    if (hasLidar && lidarFaultCount == 1) {
      return const _AutowareMode(
        name: 'LiDAR partial fusion',
        localization: 'Remaining LiDARs + GNSS + Camera',
        planning: 'Lane change constrained',
        control: 'Confidence-based cap',
        color: Color(0xFFF59E0B),
      );
    }
    if (hasCamera) {
      return const _AutowareMode(
        name: 'LiDAR + GNSS',
        localization: 'NDT LiDAR + GNSS',
        planning: 'Route keep',
        control: '45 km/h cap',
        color: Color(0xFFF59E0B),
      );
    }
    if (hasGnss) {
      return const _AutowareMode(
        name: 'LiDAR + Camera',
        localization: 'LiDAR odometry + lane',
        planning: 'Local map confidence',
        control: 'Lateral smoothing',
        color: Color(0xFFF59E0B),
      );
    }
    if (hasLidar) {
      return const _AutowareMode(
        name: 'GNSS + Camera',
        localization: 'GNSS + visual lane',
        planning: 'Radar fallback',
        control: '35 km/h cap',
        color: Color(0xFFF59E0B),
      );
    }
    return const _AutowareMode(
      name: 'Triple sensor',
      localization: 'LiDAR NDT + GNSS + Camera',
      planning: 'Autoware normal route',
      control: 'Normal MPC control',
      color: Color(0xFF16A34A),
    );
  }
}
