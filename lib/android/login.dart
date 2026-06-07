import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_widgets.dart';
import 'chat.dart';
import 'google_auth_config.dart';
import 'register.dart' show RegisterScreen;
import 'server_discovery.dart';

const authResponseTimeout = Duration(seconds: 20);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
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
    unawaited(_discoverServerSilently());
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
        backgroundColor: const Color(0xFFD92D20),
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
      'Nu am gasit serverul. Verifica adresa serverului si conexiunea.',
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
      '[LOGIN_FLOW] start auth type=${authPayload['type']} host=$_serverHost',
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
              ? 'Autentificare esuata'
              : errorMessage,
        );
        _stopLoading();
      }
    } on TimeoutException {
      _showError('Timeout la autentificare. Verifica serverul si conexiunea.');
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
      _showError('GOOGLE_WEB_CLIENT_ID nu este setat.');
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
      _showError(googleSignInErrorMessage(e));
      _stopLoading();
    }
  }

  Future<void> _loginWithPassword() async {
    final username = usernameController.text.trim();
    final password = passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError('Va rugam sa introduceti username si parola');
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF9FAF6),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              color: const Color(0xFF101828),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B5F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Chat Social',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Conecteaza-te la conversatiile tale.',
                    style: TextStyle(color: Color(0xFFD0D5DD), fontSize: 16),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Autentificare',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Introdu datele contului pentru a intra in aplicatie.',
                      style: TextStyle(color: Color(0xFF667085), fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: usernameController,
                      decoration: authInputDecoration(
                        label: 'Nume de utilizator',
                        icon: Icons.person_outline,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 10),
                    PasswordField(controller: passwordController),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 52,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : FilledButton.icon(
                              onPressed: _loginWithPassword,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B5F),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text(
                                'Autentificare',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                setState(() {
                                  _isLoading = true;
                                });
                                await _signInWithGoogle(
                                  forceAccountPicker: true,
                                );
                              },
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Continua cu Google'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF101828),
                          side: const BorderSide(color: Color(0xFFD0D5DD)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
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
                      child: const Text('Nu ai cont? Creeaza unul acum'),
                    ),
                    if (_lastError != null) ...[
                      const SizedBox(height: 10),
                      ErrorPanel(message: _lastError!),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
      decoration: authInputDecoration(label: 'Parola', icon: Icons.lock_outline)
          .copyWith(
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
