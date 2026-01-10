import 'dart:io'; // Pentru detectarea platformei
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Platform.isWindows
              ? const Text(
                  'Aceasta este versiunea pentru Windows',
                  style: TextStyle(fontSize: 20),
                )
              : const Text(
                  'Aceasta este versiunea pentru Telefon',
                  style: TextStyle(fontSize: 15),
                ),
        ),
      ),
    );
  }
}