import 'dart:io';
import 'dart:async';
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
  bool _isLoading = false; // Adăugat pentru a gestiona starea de încărcare

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
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text(
                'Bine ați venit în Chat Social',
                style: TextStyle(
                  fontFamily: 'Arial',
                  fontSize: 24,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color.fromARGB(255, 26, 27, 37),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 50,
                  child: PasswordField(controller: passwordController),
                ),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator() // Indicator de încărcare
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
                          print(
                            '[DEBUG] Încep procesul de autentificare pentru utilizatorul: $username',
                          );

                          // Trimite datele de autentificare direct la server
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
                            print('[DEBUG] Received message: $message');
                            final data = jsonDecode(message);
                            print('[DEBUG] Message type: ${data['type']}');
                            
                            if (data['type'] == 'auth_success') {
                              print(
                                '[DEBUG] Autentificare reușită pentru utilizatorul: $username',
                              );
                              if (mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ChatScreen(username: username, channel: channel),
                                  ),
                                );
                              }
                            } else if (data['type'] == 'auth_error') {
                              print(
                                '[DEBUG] Autentificare eșuată: ${data['message']}',
                              );
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
                              print('[DEBUG] Server welcome message');
                            }
                          }, onError: (error) {
                            print('[DEBUG] WebSocket error: $error');
                            channel.sink.close();
                          }, onDone: () {
                            print('[DEBUG] WebSocket done');
                          });
                          
                        } catch (e) {
                          print(
                            '[DEBUG] Excepție în procesul de autentificare: $e',
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('A apărut o eroare: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          // Reset loading state only on error
                          setState(() {
                            _isLoading = false;
                          });
                        }
                        // Note: Don't reset _isLoading on success - it will be reset when navigating
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          201,
                          173,
                          167,
                        ),
                        foregroundColor: const Color.fromARGB(255, 26, 27, 37),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Autentificare',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
              const SizedBox(height: 50),
            ],
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

Future<bool> checkServerOnline() async {
  try {
    print('[DEBUG] Încep verificarea serverului...');

    // Încearcă să se conecteze
    final channel = WebSocketChannel.connect(Uri.parse(host));
    print('[DEBUG] Încerc să mă conectez la: $host');
    final completer = Completer<bool>();

    // Timeout de 5 secunde pentru conexiune
    Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        print('[DEBUG] Timeout atins. Serverul nu a răspuns.');
        channel.sink.close();
        completer.complete(false);
      }
    });

    // Ascultă mesajele sau erorile
    channel.stream.listen(
      (message) {
        print('[DEBUG] Conexiune reușită cu serverul.');
        if (!completer.isCompleted) {
          channel.sink.close();
          completer.complete(true);
        }
      },
      onError: (error) {
        print('[DEBUG] Eroare la conectarea la server: $error');
        if (!completer.isCompleted) {
          channel.sink.close();
          completer.complete(false);
        }
      },
      onDone: () {
        print('[DEBUG] Conexiunea cu serverul s-a încheiat.');
      },
    );

    return completer.future;
  } catch (e) {
    print('[DEBUG] Eroare la verificarea serverului: $e');
    return false;
  }
}

Future<bool> authenticateUser(String username, String password) async {
  try {
    final file = File('lib/password.txt');
    final lines = await file.readAsLines();

    for (var line in lines) {
      final parts = line.split(':');
      if (parts.length == 2) {
        final fileUsername = parts[0].trim();
        final filePassword = parts[1].trim();

        if (fileUsername == username && filePassword == password) {
          return true;
        }
      }
    }
  } catch (e) {
    return false;
  }

  return false;
}
