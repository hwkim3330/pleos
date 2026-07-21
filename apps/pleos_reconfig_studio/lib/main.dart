import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/car_viewer_screen.dart';

void main() => runApp(const ProviderScope(child: MyApp()));

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PLEOS Reconfig Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff8fafc),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff155eef),
          brightness: Brightness.light,
        ),
      ),
      home: const CarViewerScreen(),
    );
  }
}
