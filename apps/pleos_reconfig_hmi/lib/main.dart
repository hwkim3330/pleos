import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'console_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The operator surface is a landscape tablet on a bench; a portrait rotation
  // mid-demo would reflow the schematic for no reason.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ReconfigHmiApp());
}

class ReconfigHmiApp extends StatelessWidget {
  const ReconfigHmiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PLEOS Reconfig HMI',
      debugShowCheckedModeBanner: false,
      theme: buildHmiTheme(),
      home: const ConsoleScreen(),
    );
  }
}
