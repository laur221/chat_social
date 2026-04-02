import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'server_discovery.dart';

import 'chat.dart';

const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue:
      '237335672620-elb89eetdgsnshh7bt4beu30jvm4a9sq.apps.googleusercontent.com',
);
const authResponseTimeout = Duration(seconds: 20);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  late final TextEditingController confirmPasswordController;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: googleWebClientId.isEmpty ? null : googleWebClientId,
  );
  bool _isLoading = false;
  String? _lastError;
  String _serverHost = configuredWsHost;

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController();
    passwordController = TextEditingController();
    confirmPasswordController = TextEditingController();
    unawaited(_discoverServerSilently());
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    final stamp = DateTime.now().toIso8601String();
    debugPrint('[REGISTER_ERROR][$stamp] $message');
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

  Future<void> _discoverServerSilently() async {
    final discovered = await ServerDiscovery.discoverWsHost();
    if (!mounted || discovered == null || discovered.isEmpty) return;
    setState(() {
      _serverHost = discovered;
    });
  }

  Future<bool> _ensureServerHost() async {
    if (_serverHost.isNotEmpty) return true;
    final discovered = await ServerDiscovery.discoverWsHost();
    if (discovered != null && discovered.isNotEmpty) {
      if (mounted) {
        setState(() {
          _serverHost = discovered;
        });
      } else {
        _serverHost = discovered;
      }
      return true;
    }
    _showError(
      'Nu am găsit serverul automat în rețea. Pornește serverul și asigură-te că telefonul e pe aceeași rețea Wi-Fi.',
    );
    return false;
  }

  Future<void> _authenticateWithPayload(
    Map<String, dynamic> authPayload, {
    required String usernameHint,
  }) async {
    if (!await _ensureServerHost()) {
      _stopLoading();
      return;
    }
    debugPrint(
      '[REGISTER_FLOW] start auth type=${authPayload['type']} host=$_serverHost usernameHint=$usernameHint',
    );
    try {
      final channel = WebSocketChannel.connect(Uri.parse(_serverHost));
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
        '[REGISTER_FLOW] server response type=${resp['type']} message=${resp['message']}',
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

  Future<void> _register() async {
    final username = usernameController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showError('Completează toate câmpurile.');
      return;
    }
    if (password != confirmPassword) {
      _showError('Parolele nu coincid.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    await _authenticateWithPayload({
      'type': 'register',
      'username': username,
      'password': password,
    }, usernameHint: username);
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
              children: [
                const Icon(
                  Icons.person_add_alt_1,
                  size: 78,
                  color: Color.fromARGB(255, 201, 173, 167),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Creează cont',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Înregistrare Chat Social',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 30),
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
                const SizedBox(height: 12),
                RegisterPasswordField(
                  controller: passwordController,
                  hintText: 'Parolă',
                ),
                const SizedBox(height: 12),
                RegisterPasswordField(
                  controller: confirmPasswordController,
                  hintText: 'Confirmă parola',
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _register,
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
                            'Creează cont',
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
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Ai deja cont? Înapoi la login'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;

  const RegisterPasswordField({
    super.key,
    required this.controller,
    required this.hintText,
  });

  @override
  State<RegisterPasswordField> createState() => _RegisterPasswordFieldState();
}

class _RegisterPasswordFieldState extends State<RegisterPasswordField> {
  bool _isObscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _isObscured,
      decoration: InputDecoration(
        hintText: widget.hintText,
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
