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
      home: Scaffold(
        body: Platform.isWindows || Platform.isLinux || Platform.isMacOS
            ? const ChatApp()
            : const ChatAppMobile(),
      ),
    );
  }
}
