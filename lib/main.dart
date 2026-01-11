import 'dart:io'; // Pentru detectarea platformei
import 'package:flutter/material.dart';
import 'windows/main.dart'; // Importă fișierul pentru PC
import 'android/main.dart'; // Importă fișierul pentru Telefon

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Platform.isWindows
            ? const ChatApp() // Încarcă widget-ul pentru PC
            : const MobileHome(), // Încarcă widget-ul pentru Telefon
      ),
    );
  }
}
