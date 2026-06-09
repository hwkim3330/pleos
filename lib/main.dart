import 'dart:async';
import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' hide Path;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MrmDemoApp());
}

class MrmDemoApp extends StatelessWidget {
  const MrmDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Drive Pilot',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
      ),
      home: const MrmDashboard(),
    );
  }
}

class MrmDashboard extends StatefulWidget {
  const MrmDashboard({super.key});

  @override
  State<MrmDashboard> createState() => _MrmDashboardState();
}

class _MrmDashboardState extends State<MrmDashboard> {
  final _hub = VirtualSensorHub();
  late SensorFrame _frame;
  Timer? _timer;
  DriveMode _mode = DriveMode.highway;
  DemoInjection _demoInjection = DemoInjection.none;
  PleosCapabilitySnapshot? _pleos;
  PleosVehicleSnapshot? _vehicle;
  ExternalDriveControl? _control;
  bool _autoMrm = true;

  @override
  void initState() {
    super.initState();
    _frame = _hub.next(
      mode: _mode,
      forceMrm: _autoMrm,
      injection: _demoInjection,
      control: _control,
    );
    _loadPleosSnapshot();
    _loadVehicleSnapshot();
    _timer = Timer.periodic(const Duration(milliseconds: 780), (_) {
      if (!mounted) return;
      setState(
        () => _frame = _hub.next(
          mode: _mode,
          forceMrm: _autoMrm,
          injection: _demoInjection,
          control: _control,
        ),
      );
      _loadVehicleSnapshot();
    });
  }

  Future<void> _loadPleosSnapshot() async {
    final snapshot = await PleosBridge.getCapabilitySnapshot();
    if (!mounted) return;
    setState(() => _pleos = snapshot);
  }

  Future<void> _loadVehicleSnapshot() async {
    final snapshot = await PleosBridge.getVehicleSnapshot();
    final control = await PleosBridge.getControlSnapshot();
    if (!mounted) return;
    setState(() {
      _vehicle = snapshot;
      _control = control;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assessment = MrmController.assess(_frame);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              _TopStatusBar(
                frame: _frame,
                assessment: assessment,
                autoMrm: _autoMrm,
              ),
              Expanded(
                child: _AutowareMrmSurface(
                  frame: _frame,
                  assessment: assessment,
                  pleos: _pleos,
                  vehicle: _vehicle,
                ),
              ),
              _BottomDock(
                mode: _mode,
                injection: _demoInjection,
                autoMrm: _autoMrm,
                onModeChanged: (mode) => setState(() => _mode = mode),
                onInjectionChanged: (injection) =>
                    setState(() => _demoInjection = injection),
                onAutoChanged: () => setState(() => _autoMrm = !_autoMrm),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar({
    required this.frame,
    required this.assessment,
    required this.autoMrm,
  });

  final SensorFrame frame;
  final MrmAssessment assessment;
  final bool autoMrm;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE3E6EA), width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.lock_rounded, size: 16, color: Color(0xFF30343A)),
            const SizedBox(width: 12),
            Text(
              'Drive Pilot',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.78),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            _TinyPill(
              icon: autoMrm
                  ? Icons.verified_rounded
                  : Icons.pause_circle_rounded,
              label: autoMrm ? 'Auto Safety' : 'Manual',
              color: autoMrm
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 36),
            Icon(Icons.route_rounded, size: 15, color: assessment.color),
            const SizedBox(width: 4),
            Text(
              assessment.label,
              style: TextStyle(
                color: assessment.color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 16),
            const Icon(
              Icons.battery_std_rounded,
              size: 15,
              color: Color(0xFF10B981),
            ),
            const SizedBox(width: 4),
            const Text(
              '82%',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${frame.speedKph.toStringAsFixed(0)} km/h',
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.wifi_rounded, size: 15, color: Color(0xFF6B7280)),
            const SizedBox(width: 10),
            const Icon(
              Icons.signal_cellular_alt_rounded,
              size: 14,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 12),
            Text(
              time,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutowareMrmSurface extends StatelessWidget {
  const _AutowareMrmSurface({
    required this.frame,
    required this.assessment,
    required this.pleos,
    required this.vehicle,
  });

  final SensorFrame frame;
  final MrmAssessment assessment;
  final PleosCapabilitySnapshot? pleos;
  final PleosVehicleSnapshot? vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1F4F7),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _AutowareHeader(frame: frame, assessment: assessment),
          const SizedBox(height: 10),
          _PleosSdkStrip(snapshot: pleos),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      Expanded(
                        child: _NavigationMapCard(
                          frame: frame,
                          assessment: assessment,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MrmPlanSheet(frame: frame, assessment: assessment),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 6,
                        child: _VehicleFeedCard(
                          frame: frame,
                          assessment: assessment,
                          vehicle: vehicle,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 4,
                        child: _EventLogCard(
                          frame: frame,
                          assessment: assessment,
                        ),
                      ),
                    ],
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

class _AutowareHeader extends StatelessWidget {
  const _AutowareHeader({required this.frame, required this.assessment});

  final SensorFrame frame;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final profile = _AutowareProfile.from(frame, assessment);
    return _SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: assessment.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(assessment.icon, color: assessment.color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.stateName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${profile.localizationMode}  ·  ${profile.pipelineType}  ·  ${profile.selectedStack}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _TinyPill(
            icon: Icons.hub_rounded,
            label: 'Fusion ${(frame.fusionConfidence * 100).round()}%',
            color: assessment.color,
          ),
          const SizedBox(width: 8),
          _TinyPill(
            icon: Icons.timer_rounded,
            label: '${profile.latencyMs} ms',
            color: const Color(0xFF2563EB),
          ),
        ],
      ),
    );
  }
}

class _PleosSdkStrip extends StatelessWidget {
  const _PleosSdkStrip({required this.snapshot});

  final PleosCapabilitySnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final items =
        snapshot?.items ??
        const [
          PleosCapability('Vehicle', 'checking', false),
          PleosCapability('Navi', 'checking', false),
          PleosCapability('ADAS', 'checking', false),
          PleosCapability('Fused', 'checking', false),
          PleosCapability('Gleo', 'checking', false),
          PleosCapability('Fleet', 'cloud', true),
          PleosCapability('Data', 'cloud', true),
        ];
    return _SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.api_rounded, size: 16, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          const Text(
            'Pleos SDK/API',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in items) ...[
                    _SdkChip(item: item),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SdkChip extends StatelessWidget {
  const _SdkChip({required this.item});

  final PleosCapability item;

  @override
  Widget build(BuildContext context) {
    final color = item.available
        ? const Color(0xFF10B981)
        : const Color(0xFFF59E0B);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.available ? Icons.check_circle_rounded : Icons.pending_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            item.name,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            item.status,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationMapCard extends StatelessWidget {
  const _NavigationMapCard({required this.frame, required this.assessment});

  final SensorFrame frame;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final profile = _AutowareProfile.from(frame, assessment);
    final traveled = _RouteModel.traveled(frame.routeProgress);
    final remaining = _RouteModel.remaining(frame.routeProgress);
    return _SurfaceCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: frame.location,
                initialZoom: 15.4,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.mrm_multimodal_demo',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _RouteModel.points,
                      color: const Color(0xFF94A3B8).withValues(alpha: 0.55),
                      strokeWidth: 7,
                    ),
                    Polyline(
                      points: remaining,
                      color: const Color(0xFF2563EB),
                      strokeWidth: 6,
                    ),
                    Polyline(
                      points: traveled,
                      color: assessment.color,
                      strokeWidth: 6,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _RouteModel.destination,
                      width: 38,
                      height: 38,
                      child: const _MapPin(),
                    ),
                    Marker(
                      point: frame.location,
                      width: 54,
                      height: 54,
                      child: Transform.rotate(
                        angle: frame.headingRad,
                        child: Container(
                          decoration: BoxDecoration(
                            color: assessment.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: assessment.color.withValues(alpha: 0.35),
                                blurRadius: 18,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 14,
              top: 14,
              right: 14,
              child: _MapGuidanceBar(frame: frame, assessment: assessment),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Row(
                children: [
                  _MapMetric(
                    icon: Icons.speed_rounded,
                    label: 'Speed',
                    value: '${frame.speedKph.round()} km/h',
                  ),
                  const SizedBox(width: 8),
                  _MapMetric(
                    icon: Icons.route_rounded,
                    label: 'Remain',
                    value:
                        '${(frame.remainingDistanceM / 1000).toStringAsFixed(1)} km',
                  ),
                  const SizedBox(width: 8),
                  _MapMetric(
                    icon: Icons.hub_rounded,
                    label: 'Mode',
                    value: profile.shortMode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGuidanceBar extends StatelessWidget {
  const _MapGuidanceBar({required this.frame, required this.assessment});

  final SensorFrame frame;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.turn_right_rounded, color: assessment.color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  frame.nextInstruction,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${frame.etaMinutes} min  ·  ${(frame.remainingDistanceM / 1000).toStringAsFixed(1)} km  ·  ${assessment.step.shortLabel}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TinyPill(
            icon: assessment.icon,
            label: assessment.label,
            color: assessment.color,
          ),
        ],
      ),
    );
  }
}

class _MapMetric extends StatelessWidget {
  const _MapMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF2563EB)),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.location_on_rounded,
      color: Color(0xFF7C3AED),
      size: 38,
    );
  }
}

class LocalizationPipelineCard extends StatelessWidget {
  const LocalizationPipelineCard({
    super.key,
    required this.frame,
    required this.assessment,
  });

  final SensorFrame frame;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final profile = _AutowareProfile.from(frame, assessment);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.my_location_rounded,
            title: 'Localization Multi-Mode',
            trailing: profile.pipelineType,
            color: assessment.color,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: CustomPaint(
              painter: _PipelinePainter(
                profile: profile,
                assessment: assessment,
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: const Alignment(-0.78, -0.48),
                    child: _PipelineNode(
                      label: 'LiDAR',
                      health: frame.lidar.health,
                      used: profile.absoluteSensors.contains('LiDAR'),
                      icon: Icons.radar_rounded,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, -0.62),
                    child: _PipelineNode(
                      label: 'GNSS',
                      health: frame.gnss.health,
                      used: profile.absoluteSensors.contains('GNSS'),
                      icon: Icons.satellite_alt_rounded,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0.78, -0.48),
                    child: _PipelineNode(
                      label: 'Camera',
                      health: frame.camera.health,
                      used: profile.absoluteSensors.contains('Camera'),
                      icon: Icons.videocam_rounded,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(-0.42, 0.26),
                    child: _PipelineNode(
                      label: 'IMU',
                      health: frame.imu.health,
                      used: true,
                      icon: Icons.screen_rotation_alt_rounded,
                      compact: true,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0.42, 0.26),
                    child: _PipelineNode(
                      label: 'Odom',
                      health: frame.odometryHealth,
                      used: true,
                      icon: Icons.speed_rounded,
                      compact: true,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.82),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: assessment.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        profile.fusionMethod,
                        style: TextStyle(
                          color: assessment.color,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SmallMetric(label: 'Mode', value: profile.shortMode),
              const SizedBox(width: 8),
              _SmallMetric(label: 'E2E', value: '${profile.e2eLatencyMs}ms'),
              const SizedBox(width: 8),
              _SmallMetric(
                label: 'Saving',
                value: '${profile.resourceSaving}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StackCard extends StatelessWidget {
  const StackCard({super.key, required this.frame, required this.assessment});

  final SensorFrame frame;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final profile = _AutowareProfile.from(frame, assessment);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.account_tree_rounded,
            title: 'Selected Autoware Stack',
            trailing: profile.safetyState,
            color: assessment.color,
          ),
          const SizedBox(height: 12),
          Text(
            profile.selectedStack,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            profile.stackReason,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.7,
              children: [
                for (final module in profile.modules)
                  _ModuleTile(module: module),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleFeedCard extends StatelessWidget {
  const _VehicleFeedCard({
    required this.frame,
    required this.assessment,
    required this.vehicle,
  });

  final SensorFrame frame;
  final MrmAssessment assessment;
  final PleosVehicleSnapshot? vehicle;

  @override
  Widget build(BuildContext context) {
    final snapshot = vehicle ?? PleosVehicleSnapshot.demo(frame);
    final items = snapshot.displayItems(frame);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.directions_car_filled_rounded,
            title: 'Pleos Vehicle Feed',
            trailing: snapshot.source,
            color: assessment.color,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _VehicleHeroMetric(
                  label: 'Vehicle Speed',
                  value: snapshot.speedText(frame),
                  icon: Icons.speed_rounded,
                  color: assessment.color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VehicleHeroMetric(
                  label: 'Gear',
                  value: snapshot.gearText,
                  icon: Icons.settings_rounded,
                  color: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.65,
              children: [
                for (final item in items)
                  _VehicleDataTile(
                    label: item.label,
                    value: item.value,
                    icon: item.icon,
                    color: item.color,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleHeroMetric extends StatelessWidget {
  const _VehicleHeroMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
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

class _VehicleDataTile extends StatelessWidget {
  const _VehicleDataTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
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

class _EventLogCard extends StatelessWidget {
  const _EventLogCard({required this.frame, required this.assessment});

  final SensorFrame frame;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final profile = _AutowareProfile.from(frame, assessment);
    final events = [
      ('INFO', 'Scenario: ${frame.events.first}'),
      ('INFO', 'Localization mode ${profile.localizationMode}'),
      if (assessment.step.index >= MrmStep.warning.index)
        ('WARN', assessment.reason)
      else
        ('OK', 'Autoware stack operating within nominal safety bounds.'),
      ('SAFE', 'Command: ${assessment.command}'),
    ];
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.timeline_rounded,
            title: 'Event Timeline',
            trailing: profile.transitionStatus,
            color: assessment.color,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final event = events[index];
                final color = switch (event.$1) {
                  'WARN' => const Color(0xFFF59E0B),
                  'SAFE' => assessment.color,
                  'OK' => const Color(0xFF10B981),
                  _ => const Color(0xFF2563EB),
                };
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${event.$1}  ${event.$2}',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 11,
                          height: 1.28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 9),
              itemCount: events.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          trailing,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PipelineNode extends StatelessWidget {
  const _PipelineNode({
    required this.label,
    required this.health,
    required this.used,
    required this.icon,
    this.compact = false,
  });

  final String label;
  final double health;
  final bool used;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = !used
        ? const Color(0xFF9CA3AF)
        : health > 0.72
        ? const Color(0xFF10B981)
        : health > 0.48
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);
    return Container(
      width: compact ? 88 : 100,
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11, vertical: 9),
      decoration: BoxDecoration(
        color: used ? color.withValues(alpha: 0.11) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: used ? color.withValues(alpha: 0.30) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: compact ? 15 : 17),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: used
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF),
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  used ? '${(health * 100).round()}%' : 'off',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
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

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final _ModuleState module;

  @override
  Widget build(BuildContext context) {
    final color = module.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(module.icon, color: color, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              module.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            module.status,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelinePainter extends CustomPainter {
  _PipelinePainter({required this.profile, required this.assessment});

  final _AutowareProfile profile;
  final MrmAssessment assessment;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.60);
    final sensors = [
      (
        Offset(size.width * 0.18, size.height * 0.28),
        profile.absoluteSensors.contains('LiDAR'),
      ),
      (
        Offset(size.width * 0.50, size.height * 0.20),
        profile.absoluteSensors.contains('GNSS'),
      ),
      (
        Offset(size.width * 0.82, size.height * 0.28),
        profile.absoluteSensors.contains('Camera'),
      ),
      (Offset(size.width * 0.34, size.height * 0.66), true),
      (Offset(size.width * 0.66, size.height * 0.66), true),
    ];
    for (final sensor in sensors) {
      final paint = Paint()
        ..color = (sensor.$2 ? assessment.color : const Color(0xFFCBD5E1))
            .withValues(alpha: sensor.$2 ? 0.36 : 0.18)
        ..strokeWidth = sensor.$2 ? 2.4 : 1.3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(sensor.$1, center, paint);
    }
    canvas.drawCircle(
      center,
      36,
      Paint()..color = assessment.color.withValues(alpha: 0.10),
    );
    canvas.drawCircle(
      center,
      22,
      Paint()..color = assessment.color.withValues(alpha: 0.18),
    );
    canvas.drawCircle(center, 7, Paint()..color = assessment.color);
  }

  @override
  bool shouldRepaint(covariant _PipelinePainter oldDelegate) {
    return oldDelegate.profile != profile ||
        oldDelegate.assessment != assessment;
  }
}

class _AutowareProfile {
  const _AutowareProfile({
    required this.stateName,
    required this.transitionStatus,
    required this.localizationMode,
    required this.shortMode,
    required this.pipelineType,
    required this.absoluteSensors,
    required this.selectedStack,
    required this.stackReason,
    required this.fusionMethod,
    required this.safetyState,
    required this.latencyMs,
    required this.e2eLatencyMs,
    required this.resourceSaving,
    required this.modules,
  });

  final String stateName;
  final String transitionStatus;
  final String localizationMode;
  final String shortMode;
  final String pipelineType;
  final List<String> absoluteSensors;
  final String selectedStack;
  final String stackReason;
  final String fusionMethod;
  final String safetyState;
  final int latencyMs;
  final int e2eLatencyMs;
  final int resourceSaving;
  final List<_ModuleState> modules;

  static _AutowareProfile from(SensorFrame frame, MrmAssessment assessment) {
    final healthy = <String>[
      if (frame.lidar.health > 0.50) 'LiDAR',
      if (frame.gnss.health > 0.50) 'GNSS',
      if (frame.camera.health > 0.50) 'Camera',
    ];
    final sensors = assessment.step == MrmStep.stop ? <String>[] : healthy;
    final mode = sensors.isEmpty
        ? 'UNAVAILABLE'
        : sensors.join('_').toUpperCase();
    final pipeline = switch (sensors.length) {
      0 => 'UNAVAILABLE',
      1 => 'SINGLE',
      2 => 'DUAL',
      _ => 'TRIPLE',
    };
    final stack = switch (assessment.step) {
      MrmStep.nominal => 'TRIPLE_FUSION_STACK',
      MrmStep.degraded =>
        'DUAL_${sensors.take(2).join('_').toUpperCase()}_STACK',
      MrmStep.warning =>
        sensors.length <= 1
            ? 'SINGLE_SENSOR_FALLBACK_STACK'
            : 'DUAL_SENSOR_FUSION_STACK',
      MrmStep.maneuver => 'FALLBACK_CONTROL_STACK',
      MrmStep.stop => 'FALLBACK_STOP_STACK',
    };
    final state = switch (assessment.step) {
      MrmStep.nominal => 'S1 Normal Full Stack',
      MrmStep.degraded => 'S4 Dual Sensor Fusion',
      MrmStep.warning => 'S5 Single Sensor Fallback',
      MrmStep.maneuver => 'S5 Controlled Fallback',
      MrmStep.stop => 'S6 Localization Unavailable — Safe Stop',
    };
    final safety = switch (assessment.step) {
      MrmStep.nominal || MrmStep.degraded => 'SAFE',
      MrmStep.warning => 'LIMITED_DRIVE',
      MrmStep.maneuver => 'FAIL_SAFE',
      MrmStep.stop => 'SAFE_STOP_REQUIRED',
    };
    final latency = 34 + ((1 - frame.fusionConfidence) * 95).round();
    return _AutowareProfile(
      stateName: state,
      transitionStatus: assessment.step.index >= MrmStep.warning.index
          ? 'SWITCHING'
          : 'COMPLETED',
      localizationMode: mode,
      shortMode: sensors.isEmpty
          ? 'NONE'
          : sensors.map((s) => s.substring(0, min(3, s.length))).join('+'),
      pipelineType: pipeline,
      absoluteSensors: sensors,
      selectedStack: stack,
      stackReason: assessment.step == MrmStep.nominal
          ? 'All absolute localization sensors are available; full sensing, perception, planning, and control are active.'
          : assessment.reason,
      fusionMethod: pipeline == 'TRIPLE'
          ? 'Weighted Triple Fusion'
          : pipeline == 'DUAL'
          ? 'Dual Pipeline Fusion'
          : pipeline == 'SINGLE'
          ? 'Single Absolute + Relative'
          : 'Safety Stop',
      safetyState: safety,
      latencyMs: latency,
      e2eLatencyMs: latency + 42,
      resourceSaving: assessment.step == MrmStep.nominal
          ? 0
          : min(48, assessment.step.index * 11),
      modules: _modulesFor(assessment),
    );
  }

  static List<_ModuleState> _modulesFor(MrmAssessment assessment) {
    _ModuleState m(String name, String status, IconData icon) =>
        _ModuleState(name, status, icon);
    return switch (assessment.step) {
      MrmStep.nominal => [
        m('Sensing', 'RUN', Icons.sensors_rounded),
        m('Localization', 'RUN', Icons.my_location_rounded),
        m('Perception', 'RUN', Icons.visibility_rounded),
        m('Planning', 'RUN', Icons.route_rounded),
        m('Control', 'RUN', Icons.tune_rounded),
        m('Vehicle IF', 'RUN', Icons.directions_car_rounded),
      ],
      MrmStep.degraded || MrmStep.warning => [
        m('Sensing', 'LIMIT', Icons.sensors_rounded),
        m('Localization', 'LIMIT', Icons.my_location_rounded),
        m('Perception', 'RUN', Icons.visibility_rounded),
        m('Planning', 'RUN', Icons.route_rounded),
        m('Control', 'RUN', Icons.tune_rounded),
        m('Pleos Nav', 'SYNC', Icons.navigation_rounded),
      ],
      MrmStep.maneuver => [
        m('Sensing', 'LIMIT', Icons.sensors_rounded),
        m('Localization', 'LIMIT', Icons.my_location_rounded),
        m('Perception', 'LIMIT', Icons.visibility_rounded),
        m('Planning', 'SAFE', Icons.route_rounded),
        m('Control', 'SAFE', Icons.tune_rounded),
        m('Hazard', 'ON', Icons.emergency_share_rounded),
      ],
      MrmStep.stop => [
        m('Sensing', 'ERROR', Icons.sensors_rounded),
        m('Localization', 'ERROR', Icons.my_location_rounded),
        m('Perception', 'STOP', Icons.visibility_off_rounded),
        m('Planning', 'STOP', Icons.route_rounded),
        m('Control', 'BRAKE', Icons.tune_rounded),
        m('Vehicle IF', 'SAFE', Icons.directions_car_rounded),
      ],
    };
  }
}

class _ModuleState {
  const _ModuleState(this.name, this.status, this.icon);

  final String name;
  final String status;
  final IconData icon;

  Color get color {
    return switch (status) {
      'RUN' || 'ON' || 'SYNC' => const Color(0xFF10B981),
      'LIMIT' || 'SAFE' || 'BRAKE' => const Color(0xFFF59E0B),
      'ERROR' || 'STOP' => const Color(0xFFEF4444),
      _ => const Color(0xFF9CA3AF),
    };
  }
}

class _MrmPlanSheet extends StatelessWidget {
  const _MrmPlanSheet({required this.frame, required this.assessment});

  final SensorFrame frame;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Safety Mode Plan',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _TinyPill(
                icon: Icons.hub_rounded,
                label: 'Fusion ${(frame.fusionConfidence * 100).round()}%',
                color: assessment.color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final step in MrmStep.values) ...[
                Expanded(
                  child: _PlanStep(step: step, assessment: assessment),
                ),
                if (step != MrmStep.values.last) const SizedBox(width: 7),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MrmMetric(
                icon: Icons.timer_rounded,
                label: 'TTC',
                value: '${frame.ttcSec.toStringAsFixed(1)}s',
              ),
              const SizedBox(width: 10),
              _MrmMetric(
                icon: Icons.social_distance_rounded,
                label: 'Lead',
                value: '${frame.leadDistanceM.toStringAsFixed(1)}m',
              ),
              const SizedBox(width: 10),
              _MrmMetric(
                icon: Icons.near_me_rounded,
                label: 'Lane',
                value: '${frame.laneOffsetM.toStringAsFixed(2)}m',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanStep extends StatelessWidget {
  const _PlanStep({required this.step, required this.assessment});

  final MrmStep step;
  final MrmAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final active = step.index <= assessment.step.index;
    final current = step == assessment.step;
    final color = current
        ? assessment.color
        : active
        ? const Color(0xFF2563EB)
        : const Color(0xFFD1D5DB);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: current
            ? color.withValues(alpha: 0.11)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: current ? color.withValues(alpha: 0.34) : Colors.transparent,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            current
                ? Icons.radio_button_checked_rounded
                : Icons.check_circle_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            step.shortLabel,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.mode,
    required this.injection,
    required this.autoMrm,
    required this.onModeChanged,
    required this.onInjectionChanged,
    required this.onAutoChanged,
  });

  final DriveMode mode;
  final DemoInjection injection;
  final bool autoMrm;
  final ValueChanged<DriveMode> onModeChanged;
  final ValueChanged<DemoInjection> onInjectionChanged;
  final VoidCallback onAutoChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        border: Border(top: BorderSide(color: Color(0xFFE3E6EA), width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _DockIcon(icon: Icons.apps_rounded, selected: false, onTap: () {}),
            const SizedBox(width: 14),
            _ModeButton(
              label: 'Highway',
              icon: Icons.alt_route_rounded,
              selected: mode == DriveMode.highway,
              onTap: () => onModeChanged(DriveMode.highway),
            ),
            const SizedBox(width: 8),
            _ModeButton(
              label: 'Urban',
              icon: Icons.location_city_rounded,
              selected: mode == DriveMode.urban,
              onTap: () => onModeChanged(DriveMode.urban),
            ),
            const SizedBox(width: 8),
            _ModeButton(
              label: 'Low Vis',
              icon: Icons.foggy,
              selected: mode == DriveMode.lowVisibility,
              onTap: () => onModeChanged(DriveMode.lowVisibility),
            ),
            const SizedBox(width: 16),
            _ModeButton(
              label: 'Clear',
              icon: Icons.play_circle_rounded,
              selected: injection == DemoInjection.none,
              onTap: () => onInjectionChanged(DemoInjection.none),
            ),
            const SizedBox(width: 8),
            _ModeButton(
              label: 'Cut-in',
              icon: Icons.call_merge_rounded,
              selected: injection == DemoInjection.cutIn,
              onTap: () => onInjectionChanged(DemoInjection.cutIn),
            ),
            const SizedBox(width: 8),
            _ModeButton(
              label: 'Sensor',
              icon: Icons.sensors_off_rounded,
              selected: injection == DemoInjection.sensorFault,
              onTap: () => onInjectionChanged(DemoInjection.sensorFault),
            ),
            const SizedBox(width: 8),
            _ModeButton(
              label: 'Stop',
              icon: Icons.emergency_rounded,
              selected: injection == DemoInjection.safeStop,
              onTap: () => onInjectionChanged(DemoInjection.safeStop),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 32, color: const Color(0xFFDDE1E6)),
            const SizedBox(width: 16),
            _DockIcon(
              icon: Icons.shield_rounded,
              selected: autoMrm,
              onTap: onAutoChanged,
            ),
            const SizedBox(width: 36),
            const Icon(
              Icons.keyboard_arrow_left_rounded,
              size: 28,
              color: Color(0xFFB6BDC6),
            ),
            const SizedBox(width: 4),
            const Text(
              'NAV',
              style: TextStyle(
                color: Color(0xFFB6BDC6),
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_right_rounded,
              size: 28,
              color: Color(0xFFB6BDC6),
            ),
            const SizedBox(width: 36),
            _DockIcon(
              icon: Icons.navigation_rounded,
              selected: true,
              onTap: () {},
            ),
            const SizedBox(width: 10),
            _DockIcon(icon: Icons.hub_rounded, selected: false, onTap: () {}),
            const SizedBox(width: 10),
            _DockIcon(icon: Icons.tune_rounded, selected: false, onTap: () {}),
          ],
        ),
      ),
    );
  }
}

class PleosBridge {
  static const _channel = MethodChannel('mrm.pilot/pleos');

  static Future<PleosCapabilitySnapshot> getCapabilitySnapshot() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'getCapabilitySnapshot',
      );
      return PleosCapabilitySnapshot.fromMap(response ?? const {});
    } on PlatformException catch (error) {
      return PleosCapabilitySnapshot.demo('bridge-error:${error.code}');
    } on MissingPluginException {
      return PleosCapabilitySnapshot.demo('flutter-demo');
    }
  }

  static Future<PleosVehicleSnapshot> getVehicleSnapshot() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'getVehicleSnapshot',
      );
      return PleosVehicleSnapshot.fromMap(response ?? const {});
    } on PlatformException catch (error) {
      return PleosVehicleSnapshot.empty('bridge-error:${error.code}');
    } on MissingPluginException {
      return PleosVehicleSnapshot.empty('flutter-demo');
    }
  }

  static Future<ExternalDriveControl?> getControlSnapshot() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'getControlSnapshot',
      );
      return ExternalDriveControl.fromMap(response ?? const {});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class PleosCapabilitySnapshot {
  const PleosCapabilitySnapshot({required this.source, required this.items});

  final String source;
  final List<PleosCapability> items;

  factory PleosCapabilitySnapshot.fromMap(Map<String, Object?> map) {
    final rawItems = map['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => PleosCapability.fromMap(item))
              .toList()
        : <PleosCapability>[];
    return PleosCapabilitySnapshot(
      source: map['source']?.toString() ?? 'pleos-bridge',
      items: items.isEmpty
          ? PleosCapabilitySnapshot.demo('no-native-items').items
          : items,
    );
  }

  factory PleosCapabilitySnapshot.demo(String source) {
    return PleosCapabilitySnapshot(
      source: source,
      items: const [
        PleosCapability('Vehicle', 'bridge', true),
        PleosCapability('Navi', 'route', true),
        PleosCapability('ADAS', 'demo', false),
        PleosCapability('Fused', 'demo', false),
        PleosCapability('Gleo', 'voice', true),
        PleosCapability('Fleet', 'cloud', true),
        PleosCapability('Data', 'cloud', true),
      ],
    );
  }
}

class PleosCapability {
  const PleosCapability(this.name, this.status, this.available);

  final String name;
  final String status;
  final bool available;

  factory PleosCapability.fromMap(Map<Object?, Object?> map) {
    return PleosCapability(
      map['name']?.toString() ?? 'SDK',
      map['status']?.toString() ?? 'unknown',
      map['available'] == true,
    );
  }
}

class PleosVehicleSnapshot {
  const PleosVehicleSnapshot({required this.source, required this.values});

  final String source;
  final Map<String, Object?> values;

  factory PleosVehicleSnapshot.fromMap(Map<String, Object?> map) {
    final rawValues = map['values'];
    return PleosVehicleSnapshot(
      source: map['source']?.toString() ?? 'vehicle-bridge',
      values: rawValues is Map
          ? rawValues.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
  }

  factory PleosVehicleSnapshot.empty(String source) {
    return PleosVehicleSnapshot(source: source, values: const {});
  }

  factory PleosVehicleSnapshot.demo(SensorFrame frame) {
    return PleosVehicleSnapshot(
      source: 'demo-feed',
      values: {
        'PERF_VEHICLE_SPEED': frame.speedKph / 3.6,
        'PERF_VEHICLE_SPEED_DISPLAY': frame.speedKph / 3.6,
        'CURRENT_GEAR': 8,
        'PERF_ODOMETER': 12482.4,
        'EV_BATTERY_LEVEL': 82.0,
        'RANGE_REMAINING': 385.0,
        'TIRE_PRESSURE': 250.0,
        'ENV_OUTSIDE_TEMPERATURE': 20.0,
        'CRUISE_CONTROL_STATE': 1,
        'LANE_KEEP_ASSIST_STATE': frame.fusionConfidence > 0.72 ? 1 : 2,
        'FORWARD_COLLISION_WARNING_STATE': frame.ttcSec < 2.8 ? 2 : 0,
        'PARKING_BRAKE_ON': false,
      },
    );
  }

  String speedText(SensorFrame fallback) {
    final speedMs =
        number('PERF_VEHICLE_SPEED_DISPLAY') ?? number('PERF_VEHICLE_SPEED');
    final speed = speedMs == null ? fallback.speedKph : speedMs * 3.6;
    return '${speed.round()} km/h';
  }

  String get gearText {
    final gear =
        number('CURRENT_GEAR')?.round() ?? number('GEAR_SELECTION')?.round();
    return switch (gear) {
      1 => 'N',
      2 => 'R',
      4 => 'P',
      8 || 16 || 32 || 64 => 'D',
      _ => '--',
    };
  }

  List<VehicleDisplayItem> displayItems(SensorFrame fallback) {
    String n(String key, String suffix, {double scale = 1, int digits = 0}) {
      final value = number(key);
      if (value == null) return '--';
      return '${(value * scale).toStringAsFixed(digits)}$suffix';
    }

    String b(String key) {
      final value = values[key];
      if (value is bool) return value ? 'ON' : 'OFF';
      if (value is num) return value == 0 ? 'OFF' : 'ON';
      return '--';
    }

    return [
      VehicleDisplayItem(
        'Odometer',
        n('PERF_ODOMETER', ' km', digits: 1),
        Icons.route_rounded,
        const Color(0xFF2563EB),
      ),
      VehicleDisplayItem(
        'Battery',
        n('EV_BATTERY_LEVEL', '%'),
        Icons.battery_charging_full_rounded,
        const Color(0xFF10B981),
      ),
      VehicleDisplayItem(
        'Range',
        n('RANGE_REMAINING', ' km'),
        Icons.ev_station_rounded,
        const Color(0xFF10B981),
      ),
      VehicleDisplayItem(
        'Tire',
        n('TIRE_PRESSURE', ' kPa'),
        Icons.tire_repair_rounded,
        const Color(0xFF64748B),
      ),
      VehicleDisplayItem(
        'Outside',
        n('ENV_OUTSIDE_TEMPERATURE', 'C', digits: 1),
        Icons.thermostat_rounded,
        const Color(0xFFF59E0B),
      ),
      VehicleDisplayItem(
        'Cruise',
        b('CRUISE_CONTROL_STATE'),
        Icons.speed_rounded,
        const Color(0xFF2563EB),
      ),
      VehicleDisplayItem(
        'Lane Assist',
        b('LANE_KEEP_ASSIST_STATE'),
        Icons.assistant_direction_rounded,
        fallback.fusionConfidence > 0.72
            ? const Color(0xFF10B981)
            : const Color(0xFFF59E0B),
      ),
      VehicleDisplayItem(
        'Forward Warn',
        b('FORWARD_COLLISION_WARNING_STATE'),
        Icons.warning_rounded,
        fallback.ttcSec < 2.8
            ? const Color(0xFFEF4444)
            : const Color(0xFF64748B),
      ),
    ];
  }

  double? number(String key) {
    final value = values[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class VehicleDisplayItem {
  const VehicleDisplayItem(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class ExternalDriveControl {
  const ExternalDriveControl({
    required this.source,
    this.speedKph,
    this.lat,
    this.lon,
    this.driveState,
  });

  final String source;
  final double? speedKph;
  final double? lat;
  final double? lon;
  final String? driveState;

  factory ExternalDriveControl.fromMap(Map<String, Object?> map) {
    final raw = map['values'];
    if (raw is! Map || raw.isEmpty) {
      return ExternalDriveControl(source: map['source']?.toString() ?? 'none');
    }
    double? number(String key) {
      final value = raw[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return ExternalDriveControl(
      source: map['source']?.toString() ?? 'intent-control',
      speedKph: number('speedKph'),
      lat: number('lat'),
      lon: number('lon'),
      driveState: raw['driveState']?.toString(),
    );
  }

  bool get hasLocation => lat != null && lon != null;
  bool get hasAny =>
      speedKph != null || hasLocation || (driveState?.isNotEmpty ?? false);
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MrmMetric extends StatelessWidget {
  const _MrmMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF6B7280), size: 17),
            const SizedBox(height: 4),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  const _TinyPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFECEFF3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: selected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF4B5563),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : const Color(0xFFECEFF3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: selected ? Colors.white : const Color(0xFF4B5563),
          size: 21,
        ),
      ),
    );
  }
}

enum DriveMode { highway, urban, lowVisibility }

enum DemoInjection { none, cutIn, sensorFault, safeStop }

enum MrmStep {
  nominal('Monitor'),
  degraded('Degraded'),
  warning('Warning'),
  maneuver('Fallback'),
  stop('Stop');

  const MrmStep(this.shortLabel);
  final String shortLabel;
}

class MrmController {
  static MrmAssessment assess(SensorFrame frame) {
    final sensorPenalty = 1 - frame.fusionConfidence;
    final ttcPenalty = ((4.5 - frame.ttcSec) / 4.5).clamp(0.0, 1.0);
    final lanePenalty = (frame.laneOffsetM.abs() / 0.95).clamp(0.0, 1.0);
    final v2xPenalty = frame.v2x.health < 0.45 ? 0.18 : 0.0;
    final risk =
        (sensorPenalty * 0.38 +
                ttcPenalty * 0.36 +
                lanePenalty * 0.18 +
                v2xPenalty)
            .clamp(0.0, 1.0);

    if (risk > 0.78 || frame.ttcSec < 1.8) {
      return MrmAssessment(
        risk: risk,
        step: MrmStep.stop,
        label: 'SAFE STOP',
        command: 'Brake + Safe Stop',
        reason:
            'Critical object proximity. Executing minimal risk stop while keeping hazard signaling active.',
        targetSpeed: 0,
        color: const Color(0xFFEF4444),
        icon: Icons.emergency_rounded,
      );
    }
    if (risk > 0.58 || frame.ttcSec < 2.7) {
      return MrmAssessment(
        risk: risk,
        step: MrmStep.maneuver,
        label: 'SAFETY ACTIVE',
        command: 'Decel + Right Lane',
        reason:
            'Cut-in object and degraded confidence require a controlled fallback path.',
        targetSpeed: 25,
        color: const Color(0xFFF97316),
        icon: Icons.assistant_direction_rounded,
      );
    }
    if (risk > 0.38 || frame.fusionConfidence < 0.68) {
      return MrmAssessment(
        risk: risk,
        step: MrmStep.warning,
        label: 'TAKEOVER READY',
        command: 'Limit Speed',
        reason: 'Fusion confidence is degraded. Fallback trajectory is armed.',
        targetSpeed: min(frame.speedKph, 55),
        color: const Color(0xFFF59E0B),
        icon: Icons.warning_rounded,
      );
    }
    if (frame.fusionConfidence < 0.82) {
      return MrmAssessment(
        risk: risk,
        step: MrmStep.degraded,
        label: 'DEGRADED',
        command: 'Monitor',
        reason: 'One sensor group is soft degraded, but fusion remains stable.',
        targetSpeed: frame.speedKph,
        color: const Color(0xFF2563EB),
        icon: Icons.sensors_rounded,
      );
    }
    return MrmAssessment(
      risk: risk,
      step: MrmStep.nominal,
      label: 'NOMINAL',
      command: 'Cruise',
      reason:
          'All virtual sensors are coherent. Autonomous stack remains nominal.',
      targetSpeed: frame.speedKph,
      color: const Color(0xFF10B981),
      icon: Icons.verified_rounded,
    );
  }
}

class VirtualSensorHub {
  final Random _random = Random();
  int _tick = 0;

  SensorFrame next({
    required DriveMode mode,
    required bool forceMrm,
    required DemoInjection injection,
    required ExternalDriveControl? control,
  }) {
    _tick++;
    final wave = sin(_tick / 5);
    final eventPulse =
        injection == DemoInjection.cutIn || forceMrm && _tick % 18 > 10;
    final sensorFault = injection == DemoInjection.sensorFault;
    final safeStop = injection == DemoInjection.safeStop;
    final lowVis = mode == DriveMode.lowVisibility;
    final urban = mode == DriveMode.urban;

    final cameraHealth = _health(
      base: sensorFault
          ? 0.34
          : lowVis
          ? 0.58
          : 0.9,
      volatility: lowVis ? 0.18 : 0.06,
      eventDrop: safeStop
          ? 0.46
          : eventPulse
          ? 0.24
          : 0,
    );
    final lidarHealth = _health(
      base: sensorFault
          ? 0.42
          : lowVis
          ? 0.74
          : 0.88,
      volatility: 0.09,
      eventDrop: safeStop
          ? 0.38
          : eventPulse
          ? 0.12
          : 0,
    );
    final radarHealth = _health(
      base: safeStop ? 0.32 : 0.92,
      volatility: 0.05,
      eventDrop: 0,
    );
    final gnssHealth = _health(
      base: sensorFault
          ? 0.38
          : urban
          ? 0.68
          : 0.86,
      volatility: urban ? 0.16 : 0.06,
      eventDrop: safeStop ? 0.34 : 0,
    );
    final imuHealth = _health(
      base: safeStop ? 0.58 : 0.93,
      volatility: 0.03,
      eventDrop: 0,
    );
    final v2xHealth = _health(
      base: sensorFault
          ? 0.40
          : urban
          ? 0.72
          : 0.84,
      volatility: 0.18,
      eventDrop: safeStop
          ? 0.36
          : eventPulse
          ? 0.22
          : 0,
    );
    final simulatedSpeed = safeStop
        ? 28 + wave * 3
        : urban
        ? 42 + wave * 7
        : 84 + wave * 9;
    final speed = control?.speedKph ?? simulatedSpeed;
    final leadDistance = safeStop
        ? 7 + _random.nextDouble() * 3
        : eventPulse
        ? 16 + _random.nextDouble() * 8
        : (urban ? 28 : 55) + cos(_tick / 4) * 18;
    final relativeSpeed = safeStop
        ? -42 - _random.nextDouble() * 10
        : eventPulse
        ? -28 - _random.nextDouble() * 10
        : -4 + sin(_tick / 3) * 8;
    final laneOffset =
        (lowVis ? 0.22 : 0.08) * sin(_tick / 2) +
        (safeStop
            ? 0.74
            : eventPulse
            ? 0.42
            : 0);
    final ttc = relativeSpeed < -1
        ? leadDistance / ((-relativeSpeed) / 3.6)
        : 9.9;
    final progress = safeStop ? min(0.98, _tick / 220) : (_tick % 220) / 220.0;
    final routePose = _RouteModel.poseAt(progress);
    final location = control?.hasLocation == true
        ? LatLng(control!.lat!, control.lon!)
        : routePose.location;
    final remainingDistance = _RouteModel.remainingDistance(progress);
    final eta = max(1, (remainingDistance / max(1, speed * 1000 / 60)).ceil());
    final confidence =
        [
          cameraHealth,
          lidarHealth,
          radarHealth,
          gnssHealth,
          imuHealth,
          v2xHealth,
        ].reduce((a, b) => a + b) /
        6;

    return SensorFrame(
      timestamp: DateTime.now(),
      speedKph: speed,
      leadDistanceM: leadDistance.clamp(8, 95),
      relativeSpeedKph: relativeSpeed,
      laneOffsetM: laneOffset,
      ttcSec: ttc.clamp(0.8, 9.9),
      fusionConfidence: confidence.clamp(0.0, 1.0),
      location: location,
      headingRad: routePose.headingRad,
      routeProgress: progress,
      remainingDistanceM: remainingDistance,
      etaMinutes: eta,
      nextInstruction: _RouteModel.instructionFor(progress, safeStop),
      camera: SensorData('Camera', Icons.videocam_rounded, cameraHealth),
      lidar: SensorData('LiDAR', Icons.radar_rounded, lidarHealth),
      radar: SensorData(
        'Radar',
        Icons.settings_input_antenna_rounded,
        radarHealth,
      ),
      gnss: SensorData('GNSS', Icons.satellite_alt_rounded, gnssHealth),
      imu: SensorData('IMU', Icons.screen_rotation_alt_rounded, imuHealth),
      v2x: SensorData('V2X', Icons.cell_tower_rounded, v2xHealth),
      hazards: _hazards(eventPulse || safeStop, urban),
      events: _events(mode, injection, eventPulse, confidence, ttc),
    );
  }

  double _health({
    required double base,
    required double volatility,
    required double eventDrop,
  }) {
    final noise = (_random.nextDouble() - 0.5) * volatility;
    return (base + noise - eventDrop).clamp(0.18, 0.99);
  }

  List<HazardBlob> _hazards(bool eventPulse, bool urban) {
    final count = urban ? 4 : 2;
    return List.generate(count, (index) {
      final hot = eventPulse && index == 0;
      return HazardBlob(
        lateral:
            (index - count / 2 + 0.5) * 0.16 +
            (_random.nextDouble() - 0.5) * 0.04,
        depth: 0.1 + index * 0.18 + _random.nextDouble() * 0.08,
        severity: hot ? 1.0 : 0.25 + _random.nextDouble() * 0.4,
        color: hot ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
      );
    });
  }

  List<String> _events(
    DriveMode mode,
    DemoInjection injection,
    bool eventPulse,
    double confidence,
    double ttc,
  ) {
    final modeLabel = switch (mode) {
      DriveMode.highway => 'Highway',
      DriveMode.urban => 'Urban',
      DriveMode.lowVisibility => 'Low visibility',
    };
    final events = <String>[
      modeLabel,
      'Fusion ${(confidence * 100).round()}%',
      'TTC ${ttc.toStringAsFixed(1)}s',
    ];
    if (injection == DemoInjection.safeStop) {
      events.add('Safe stop injected');
      events.add('Safe stop command');
    } else if (injection == DemoInjection.sensorFault) {
      events.add('Sensor fault injected');
      events.add('Fallback stack armed');
    } else if (eventPulse) {
      events.add('Cut-in object');
      events.add('Safety fallback candidate');
    } else if (confidence < 0.72) {
      events.add('Sensor degradation');
    } else {
      events.add('Path clear');
    }
    return events;
  }
}

class SensorFrame {
  const SensorFrame({
    required this.timestamp,
    required this.speedKph,
    required this.leadDistanceM,
    required this.relativeSpeedKph,
    required this.laneOffsetM,
    required this.ttcSec,
    required this.fusionConfidence,
    required this.location,
    required this.headingRad,
    required this.routeProgress,
    required this.remainingDistanceM,
    required this.etaMinutes,
    required this.nextInstruction,
    required this.camera,
    required this.lidar,
    required this.radar,
    required this.gnss,
    required this.imu,
    required this.v2x,
    required this.hazards,
    required this.events,
  });

  final DateTime timestamp;
  final double speedKph;
  final double leadDistanceM;
  final double relativeSpeedKph;
  final double laneOffsetM;
  final double ttcSec;
  final double fusionConfidence;
  final LatLng location;
  final double headingRad;
  final double routeProgress;
  final double remainingDistanceM;
  final int etaMinutes;
  final String nextInstruction;
  final SensorData camera;
  final SensorData lidar;
  final SensorData radar;
  final SensorData gnss;
  final SensorData imu;
  final SensorData v2x;
  final List<HazardBlob> hazards;
  final List<String> events;

  double get odometryHealth => ((imu.health + 0.94) / 2).clamp(0.0, 1.0);
}

class SensorData {
  const SensorData(this.name, this.icon, this.health);

  final String name;
  final IconData icon;
  final double health;
}

class _RoutePose {
  const _RoutePose(this.location, this.headingRad);

  final LatLng location;
  final double headingRad;
}

class _RouteModel {
  static const points = [
    LatLng(37.40180, 127.10895),
    LatLng(37.40238, 127.10974),
    LatLng(37.40294, 127.11104),
    LatLng(37.40350, 127.11242),
    LatLng(37.40432, 127.11328),
    LatLng(37.40512, 127.11378),
    LatLng(37.40592, 127.11464),
    LatLng(37.40636, 127.11578),
  ];

  static LatLng get destination => points.last;

  static final _distance = Distance();

  static _RoutePose poseAt(double progress) {
    final clamped = progress.clamp(0.0, 1.0);
    final target = totalDistance * clamped;
    var walked = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segment = _distance.as(LengthUnit.Meter, a, b);
      if (walked + segment >= target) {
        final t = ((target - walked) / segment).clamp(0.0, 1.0);
        final lat = a.latitude + (b.latitude - a.latitude) * t;
        final lng = a.longitude + (b.longitude - a.longitude) * t;
        return _RoutePose(
          LatLng(lat, lng),
          atan2(b.longitude - a.longitude, b.latitude - a.latitude),
        );
      }
      walked += segment;
    }
    final before = points[points.length - 2];
    final last = points.last;
    return _RoutePose(
      last,
      atan2(last.longitude - before.longitude, last.latitude - before.latitude),
    );
  }

  static List<LatLng> traveled(double progress) {
    return _slice(progress, keepBefore: true);
  }

  static List<LatLng> remaining(double progress) {
    return _slice(progress, keepBefore: false);
  }

  static double remainingDistance(double progress) {
    return totalDistance * (1 - progress.clamp(0.0, 1.0));
  }

  static String instructionFor(double progress, bool safeStop) {
    if (safeStop) return 'Safe stop bay ahead';
    if (progress < 0.25) return 'Continue on Pangyo-ro';
    if (progress < 0.55) return 'Keep right for Techno Valley';
    if (progress < 0.78) return 'Turn right in 120 m';
    return 'Arrive at enterprise support hub';
  }

  static double get totalDistance {
    var distance = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      distance += _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return distance;
  }

  static List<LatLng> _slice(double progress, {required bool keepBefore}) {
    final pose = poseAt(progress).location;
    final clamped = progress.clamp(0.0, 1.0);
    final target = totalDistance * clamped;
    var walked = 0.0;
    final result = <LatLng>[];
    if (keepBefore) result.add(points.first);
    for (var i = 0; i < points.length - 1; i++) {
      final segment = _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
      if (walked + segment < target) {
        if (keepBefore) result.add(points[i + 1]);
      } else {
        result.add(pose);
        if (!keepBefore) {
          result.addAll(points.skip(i + 1));
        }
        break;
      }
      walked += segment;
    }
    return result.length < 2 ? [pose, pose] : result;
  }
}

class HazardBlob {
  const HazardBlob({
    required this.lateral,
    required this.depth,
    required this.severity,
    required this.color,
  });

  final double lateral;
  final double depth;
  final double severity;
  final Color color;
}

class MrmAssessment {
  const MrmAssessment({
    required this.risk,
    required this.step,
    required this.label,
    required this.command,
    required this.reason,
    required this.targetSpeed,
    required this.color,
    required this.icon,
  });

  final double risk;
  final MrmStep step;
  final String label;
  final String command;
  final String reason;
  final double targetSpeed;
  final Color color;
  final IconData icon;
}
