import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 242, 233, 228),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
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
                const SizedBox(height: 15),
                SizedBox(
                  height: 60,
                  child: PasswordField(controller: passwordController),
                ),
                const SizedBox(height: 30),
                SizedBox(
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
                                  content: Text('Vă rugăm să introduceți username și parola'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              setState(() {
                                _isLoading = false;
                              });
                              return;
                            }

                            try {
                              print('[DEBUG] Login attempt for: $username');

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

                              channel.stream.listen((message) {
                                print('[DEBUG] Received: $message');
                                final data = jsonDecode(message);
                                print('[DEBUG] Type: ${data['type']}');

                                if (data['type'] == 'auth_success') {
                                  print('[DEBUG] Login success for: $username');
                                  if (mounted) {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatScreen(
                                          username: username,
                                          channel: channel,
                                        ),
                                      ),
                                    );
                                  }
                                } else if (data['type'] == 'auth_error') {
                                  print('[DEBUG] Login failed');
                                  channel.sink.close();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(data['message']),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                  setState(() {
                                    _isLoading = false;
                                  });
                                } else if (data['type'] == 'welcome') {
                                  print('[DEBUG] Welcome received');
                                }
                              }, onError: (error) {
                                print('[DEBUG] Error: $error');
                                channel.sink.close();
                              }, onDone: () {
                                print('[DEBUG] Done');
                              });
                            } catch (e) {
                              print('[DEBUG] Exception: $e');
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
                            // Note: Don't reset _isLoading on success - it will be reset when navigating
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 201, 173, 167),
                            foregroundColor: const Color.fromARGB(255, 26, 27, 37),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Autentificare',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Server: chat-social-ng2d.onrender.com',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
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
  _PasswordFieldState createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _isObscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
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
    );
  }
}
