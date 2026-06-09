import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:mrm_multimodal_demo/main.dart';

void main() {
  testWidgets('drive dashboard renders core panels', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2560, 1440));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MrmDemoApp());
    await tester.pump();

    expect(find.text('Drive Pilot'), findsWidgets);
    expect(find.text('Safety Mode Plan'), findsOneWidget);
    expect(find.text('Highway'), findsOneWidget);
  });

  testWidgets('drive dashboard uses compact Pleos slot layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(680, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MrmDemoApp());
    await tester.pump();

    expect(find.text('Continue on Pangyo-ro'), findsOneWidget);
    expect(find.text('Pleos Vehicle Feed'), findsOneWidget);
    expect(find.text('Event Timeline'), findsOneWidget);
  });
}
