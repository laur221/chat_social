import 'package:flutter/material.dart';
import 'package:window_size/window_size.dart';
import 'login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setWindowTitle('Chat Social PC');
      // setWindowMinSize(const Size(300, 200));
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat Social',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const LoginScreen(), // incepe cu login
    );
  }
}
