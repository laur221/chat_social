import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:window_size/window_size.dart';
import 'chat.dart';
import 'dart:convert';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

const host = 'wss://chat-social-ng2d.onrender.com/ws';

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController();
    passwordController = TextEditingController();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Schimbă dimensiunea ferestrei la 800x800 (fără poziție fixă)
    Future.delayed(const Duration(milliseconds: 100), () {
      setWindowMinSize(const Size(600, 600));
      setWindowMaxSize(const Size(600, 600));
    });

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 242, 233, 228),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Icon(
                  Icons.chat_bubble,
                  size: 80,
                  color: Color.fromARGB(255, 201, 173, 167),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Chat Social',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Bine ați venit',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 100),
                  child: TextField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      labelText: 'Nume de utilizator',
                      fillColor: const Color.fromARGB(255, 201, 173, 167),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.person),
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color.fromARGB(255, 26, 27, 37),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  height: 60,
                  child: PasswordField(controller: passwordController),
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 100),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: () async {
                              setState(() {
                                _isLoading = true;
                              });

                              final username = usernameController.text.trim();
                              final password = passwordController.text.trim();

                              if (username.isEmpty || password.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Vă rugăm să introduceți username și parola',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                setState(() {
                                  _isLoading = false;
                                });
                                return;
                              }

                              try {
                                // debug login attempt removed

                                final channel = WebSocketChannel.connect(
                                  Uri.parse(host),
                                );

                                channel.sink.add(
                                  jsonEncode({
                                    "type": "auth",
                                    "username": username,
                                    "password": password,
                                  }),
                                );

                                // Așteptăm 1 secundă pentru autentificare
                                await Future.delayed(const Duration(seconds: 1));
                                // Setează dimensiunea și poziția ferestrei după logare
                                await Future.delayed(const Duration(milliseconds: 100));
                                setWindowMinSize(const Size(700, 800));
                                setWindowMaxSize(Size.infinite);
                                setWindowFrame(const Rect.fromLTWH(100, 100, 900, 800));
                                if (!mounted) return;
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                      username: username,
                                      channel: channel,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                debugPrint('Login exception: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Eroare: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                setState(() {
                                  _isLoading = false;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(
                                255,
                                201,
                                173,
                                167,
                              ),
                              foregroundColor: const Color.fromARGB(
                                255,
                                26,
                                27,
                                37,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'Autentificare',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  final TextEditingController controller;

  const PasswordField({super.key, required this.controller});

  @override
  PasswordFieldState createState() => PasswordFieldState();
}

class PasswordFieldState extends State<PasswordField> {
  bool _isObscured = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 100),
      child: TextField(
        controller: widget.controller,
        obscureText: _isObscured,
        decoration: InputDecoration(
          hintText: 'Parolă',
          filled: true,
          fillColor: const Color.fromARGB(255, 201, 173, 167),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          prefixIcon: const Icon(Icons.lock),
          suffixIcon: IconButton(
            icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() {
                _isObscured = !_isObscured;
              });
            },
          ),
        ),
      ),
    );
  }
}
