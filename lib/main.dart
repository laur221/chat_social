import 'dart:io';
import 'package:flutter/material.dart';
import 'windows/main.dart';
import 'android/main.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B5F),
          primary: const Color(0xFFFF6B5F),
          secondary: const Color(0xFF2DD4A7),
          surface: const Color(0xFFF9FAF6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF9FAF6),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Platform.isWindows || Platform.isLinux || Platform.isMacOS
            ? const ChatApp()
            : const ChatAppMobile(),
      ),
    );
  }
}
