import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'link_state.dart';
import 'theme.dart';

/// The zonal schematic, drawn to the channel contract rather than to a picture of
/// a car: `tsn_front_a` is Front A to Rear, `tsn_front_b` is Front B to Rear, and
/// `tsn_rear` is the cross-link *between the two front switches*. A photoreal
/// vehicle in a white void looks impressive and tells the operator none of that.
class TopologyView extends StatefulWidget {
  const TopologyView({super.key, required this.state});

  final LinkState state;

  @override
  State<TopologyView> createState() => _TopologyViewState();
}

class _TopologyViewState extends State<TopologyView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flow,
      builder: (context, _) => CustomPaint(
        painter: _TopologyPainter(state: widget.state, phase: _flow.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Switch {
  const _Switch(this.title, this.role, this.at);
  final String title;
  final String role;
  final Offset at;
}

class _Link {
  const _Link(this.channel, this.name, this.board, this.from, this.to);
  final String channel;
  final String name;
  final String board;
  final int from;
  final int to;
}

class _TopologyPainter extends CustomPainter {
  _TopologyPainter({required this.state, required this.phase});

  final LinkState state;
  final double phase;

  /// Set once per paint, so label placement can push away from it.
  Offset centroid = Offset.zero;

  static const _switches = [
    _Switch('FRONT A', 'front zone', Offset(0.19, 0.24)),
    _Switch('FRONT B', 'front zone', Offset(0.19, 0.76)),
    _Switch('REAR R', 'rear zone', Offset(0.81, 0.50)),
  ];

  static const _links = [
    _Link('tsn_front_a', 'PATH 1', 'ESP-AR', 0, 2),
    _Link('tsn_front_b', 'PATH 2', 'ESP-BR', 1, 2),
    _Link('tsn_rear', 'PATH 3', 'ESP-AB', 0, 1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centres = [
      for (final item in _switches)
        Offset(item.at.dx * size.width, item.at.dy * size.height),
    ];
    const boxSize = Size(168, 82);
    centroid = centres.reduce((a, b) => a + b) / centres.length.toDouble();

    for (final link in _links) {
      _paintLink(canvas, link, centres[link.from], centres[link.to], boxSize);
    }
    for (var i = 0; i < _switches.length; i++) {
      _paintSwitch(canvas, _switches[i], centres[i], boxSize);
    }
  }

  /// Trims the line back to each box edge so it never runs under a label.
  (Offset, Offset) _trim(Offset from, Offset to, Size box) {
    final delta = to - from;
    final length = delta.distance;
    if (length == 0) return (from, to);
    final unit = delta / length;
    final inset = _edgeInset(unit, box) + 6;
    return (from + unit * inset, to - unit * inset);
  }

  double _edgeInset(Offset unit, Size box) {
    final halfWidth = box.width / 2;
    final halfHeight = box.height / 2;
    final byX = unit.dx.abs() < 1e-6 ? double.infinity : halfWidth / unit.dx.abs();
    final byY = unit.dy.abs() < 1e-6 ? double.infinity : halfHeight / unit.dy.abs();
    return math.min(byX, byY);
  }

  void _paintLink(Canvas canvas, _Link link, Offset a, Offset b, Size box) {
    final (from, to) = _trim(a, b, box);
    final healthy = state.linkHealthy(link.channel);
    final live = state.gatewayOnline;
    final colour = !live
        ? Tone.idle
        : healthy
        ? Tone.healthy
        : Tone.fault;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = Tone.hairline;
    canvas.drawLine(from, to, track);

    if (healthy) {
      // A slow dash flow is the only motion on the screen, so "traffic is
      // passing" reads at a glance and a stopped link is obvious without colour
      // vision.
      _paintFlow(canvas, from, to, colour, live);
    } else {
      _paintBreak(canvas, from, to, colour);
    }
    _paintLinkLabel(canvas, link, from, to, colour, healthy, live);
  }

  void _paintFlow(Canvas canvas, Offset from, Offset to, Color colour, bool live) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = colour.withValues(alpha: live ? 0.9 : 0.35);
    final total = (to - from).distance;
    const dash = 26.0;
    const gap = 18.0;
    final unit = (to - from) / total;
    final offset = live ? (phase * (dash + gap)) : 0.0;
    for (var start = offset - (dash + gap); start < total; start += dash + gap) {
      final head = math.max(start, 0.0);
      final tail = math.min(start + dash, total);
      if (tail <= head) continue;
      canvas.drawLine(from + unit * head, from + unit * tail, paint);
    }
  }

  void _paintBreak(Canvas canvas, Offset from, Offset to, Color colour) {
    final centre = (from + to) / 2;
    final total = (to - from).distance;
    final unit = (to - from) / total;
    const half = 17.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = colour;
    canvas.drawLine(from, centre - unit * half, paint);
    canvas.drawLine(centre + unit * half, to, paint);

    // The gap alone could be read as a drawing artefact, so the break is marked.
    final cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = colour;
    const arm = 8.0;
    canvas.drawLine(centre + const Offset(-arm, -arm), centre + const Offset(arm, arm), cross);
    canvas.drawLine(centre + const Offset(arm, -arm), centre + const Offset(-arm, arm), cross);
  }

  void _paintLinkLabel(
    Canvas canvas,
    _Link link,
    Offset from,
    Offset to,
    Color colour,
    bool healthy,
    bool live,
  ) {
    final centre = (from + to) / 2;
    final direction = to - from;
    // Push the label clear of the line, always on the outside of the triangle the
    // three switches form. Choosing the side per-link by hand put Path 1's label
    // inside, right on top of Path 3's.
    final normal = Offset(-direction.dy, direction.dx) / direction.distance;
    final outward = centre - centroid;
    final sign = (outward.dx * normal.dx + outward.dy * normal.dy) >= 0 ? 1.0 : -1.0;
    final anchor = centre + normal * 46 * sign;

    final status = !live
        ? 'NO LINK'
        : healthy
        ? 'NORMAL'
        : 'ISOLATED';
    final title = _text('${link.name}  ·  ${link.board}', TypeScale.label.copyWith(
      color: Tone.textSecondary,
      fontSize: 11.5,
    ));
    final value = _text(status, TypeScale.value.copyWith(color: colour, fontSize: 13));

    final width = math.max(title.width, value.width);
    final origin = Offset(anchor.dx - width / 2, anchor.dy - 17);
    title.paint(canvas, origin);
    value.paint(canvas, Offset(anchor.dx - value.width / 2, origin.dy + 16));
  }

  void _paintSwitch(Canvas canvas, _Switch item, Offset centre, Size box) {
    final rect = Rect.fromCenter(center: centre, width: box.width, height: box.height);
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rounded, Paint()..color = Tone.surfaceRaised);
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Tone.hairline,
    );

    final title = _text(item.title, TypeScale.value.copyWith(fontSize: 17, letterSpacing: 0.4));
    title.paint(canvas, Offset(centre.dx - title.width / 2, centre.dy - 22));
    final role = _text(item.role.toUpperCase(), TypeScale.label);
    role.paint(canvas, Offset(centre.dx - role.width / 2, centre.dy + 4));

    // A TSN switch is drawn with its port row, which is what makes the boxes read
    // as network equipment rather than as generic nodes.
    const ports = 6;
    const portWidth = 9.0;
    const spacing = 5.0;
    final rowWidth = ports * portWidth + (ports - 1) * spacing;
    var x = centre.dx - rowWidth / 2;
    for (var i = 0; i < ports; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centre.dy + 22, portWidth, 5),
          const Radius.circular(2),
        ),
        Paint()..color = state.gatewayOnline ? Tone.idle : Tone.hairline,
      );
      x += portWidth + spacing;
    }
  }

  TextPainter _text(String value, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter;
  }

  @override
  bool shouldRepaint(_TopologyPainter old) =>
      old.phase != phase || old.state != state;
}
