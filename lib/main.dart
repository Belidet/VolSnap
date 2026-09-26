import 'package:flutter/material.dart';
import 'camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volume Camera',
      theme: ThemeData(primarySwatch: Colors.blue, darkMode: true),
      home: const CameraScreen(),
    );
  }
}
