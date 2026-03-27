import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chat.dart';
import 'register.dart' show RegisterScreen;
import 'dart:convert';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

const host = String.fromEnvironment(
  'CHAT_WS_HOST',
  defaultValue: 'ws://192.168.1.116:10000/ws',
);
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue:
      '237335672620-elb89eetdgsnshh7bt4beu30jvm4a9sq.apps.googleusercontent.com',
);
const authResponseTimeout = Duration(seconds: 20);

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: googleWebClientId.isEmpty ? null : googleWebClientId,
  );
  bool _isLoading = false;
  String? _lastError;

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

  void _showError(String message) {
    final stamp = DateTime.now().toIso8601String();
    debugPrint('[LOGIN_ERROR][$stamp] $message');
    if (!mounted) return;
    setState(() {
      _lastError = '[$stamp] $message';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 10),
      ),
    );
  }

  void _stopLoading() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _authenticateWithPayload(
    Map<String, dynamic> authPayload, {
    required String usernameHint,
  }) async {
    debugPrint(
      '[LOGIN_FLOW] start auth type=${authPayload['type']} host=$host',
    );
    try {
      final channel = WebSocketChannel.connect(Uri.parse(host));
      channel.sink.add(jsonEncode(authPayload));

      final controller = StreamController.broadcast();
      final forwardSub = channel.stream.listen(
        (event) => controller.add(event),
        onError: (error) => controller.addError(error),
        onDone: () {
          controller.close();
        },
      );

      final resp = await controller.stream
          .map(
            (message) => jsonDecode(message as String) as Map<String, dynamic>,
          )
          .firstWhere(
            (data) =>
                data['type'] == 'auth_success' || data['type'] == 'auth_error',
          )
          .timeout(authResponseTimeout);

      if (!mounted) return;
      debugPrint(
        '[LOGIN_FLOW] server response type=${resp['type']} message=${resp['message']}',
      );
      if (resp['type'] == 'auth_success') {
        final responseUsername = (resp['username'] as String?)?.trim();
        final effectiveUsername =
            (responseUsername != null && responseUsername.isNotEmpty)
            ? responseUsername
            : usernameHint;
        setState(() {
          _lastError = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                username: effectiveUsername,
                channel: channel,
                incomingStream: controller.stream,
              ),
            ),
          );
        });
      } else {
        await forwardSub.cancel();
        try {
          channel.sink.close();
        } catch (_) {}
        final errorMessage = (resp['message'] as String?)?.trim();
        _showError(
          errorMessage == null || errorMessage.isEmpty
              ? 'Autentificare eșuată'
              : errorMessage,
        );
        _stopLoading();
      }
    } on TimeoutException {
      _showError(
        'Timeout la autentificare (>${authResponseTimeout.inSeconds}s). Verifică internetul pe telefon și conexiunea la server.',
      );
      _stopLoading();
    } catch (e) {
      _showError('Eroare la autentificare: $e');
      _stopLoading();
    }
  }

  Future<void> _clearGoogleSession() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
  }

  Future<void> _signInWithGoogle({bool forceAccountPicker = true}) async {
    if (googleWebClientId.isEmpty) {
      _showError(
        'GOOGLE_WEB_CLIENT_ID nu este setat. Rulează cu --dart-define=GOOGLE_WEB_CLIENT_ID=...',
      );
      _stopLoading();
      return;
    }
    try {
      if (forceAccountPicker) {
        await _clearGoogleSession();
      }
      final account = await _googleSignIn.signIn();
      if (account == null) {
        _stopLoading();
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        _showError('Google nu a returnat un ID token valid.');
        _stopLoading();
        return;
      }

      await _authenticateWithPayload({
        'type': 'google_auth',
        'id_token': idToken,
      }, usernameHint: account.email.split('@').first);
    } catch (e) {
      _showError('Eroare Google Sign-In: $e');
      _stopLoading();
    }
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
                  style: TextStyle(fontSize: 16, color: Colors.grey),
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
                            final username = usernameController.text.trim();
                            final password = passwordController.text.trim();

                            if (username.isEmpty || password.isEmpty) {
                              _showError(
                                'Vă rugăm să introduceți username și parola',
                              );
                              return;
                            }

                            setState(() {
                              _isLoading = true;
                            });
                            await _authenticateWithPayload({
                              'type': 'auth',
                              'username': username,
                              'password': password,
                            }, usernameHint: username);
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() {
                              _isLoading = true;
                            });
                            await _signInWithGoogle(forceAccountPicker: true);
                          },
                    icon: const Icon(Icons.login),
                    label: const Text('Continuă cu Google'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color.fromARGB(255, 26, 27, 37),
                      side: const BorderSide(
                        color: Color.fromARGB(255, 201, 173, 167),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                  child: const Text('Nu ai cont? Creează unul acum'),
                ),
                if (_lastError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      _lastError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A0000),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Server: $host',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
  PasswordFieldState createState() => PasswordFieldState();
}

class PasswordFieldState extends State<PasswordField> {
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
