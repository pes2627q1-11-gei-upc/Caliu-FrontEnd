import 'package:flutter/material.dart';

import 'data/auth_api.dart';
import 'data/auth_session.dart';
import 'data/auth_validators.dart';
import 'theme/caliu_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.notice, this.authApi, this.authSession});

  final String? notice;
  final AuthApi? authApi;
  final AuthSessionStore? authSession;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthApi _authApi = widget.authApi ?? AuthApi();
  late final AuthSessionStore _authSession =
      widget.authSession ?? AuthSession();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await _authApi.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await _authSession.saveToken(result.token);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isSubmitting = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No s’ha pogut desar la sessió de forma segura. Torna-ho a provar.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Text('Inicia sessió'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Benvingut/da de nou',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: CaliuColors.maroon,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Inicia sessió per accedir al teu perfil i les teves preferències.',
                        style: TextStyle(color: CaliuColors.textMuted),
                      ),
                      if (widget.notice case final notice?) ...[
                        const SizedBox(height: 16),
                        _LoginNotice(message: notice),
                      ],
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Correu electrònic',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: AuthValidators.email,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _isSubmitting ? null : _login(),
                        decoration: InputDecoration(
                          labelText: 'Contrasenya',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Mostra la contrasenya'
                                : 'Amaga la contrasenya',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: AuthValidators.password,
                      ),
                      if (_errorMessage case final message?) ...[
                        const SizedBox(height: 16),
                        _LoginError(message: message),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _login,
                        style: FilledButton.styleFrom(
                          backgroundColor: CaliuColors.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Inicia sessió'),
                      ),
                    ],
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

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CaliuColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CaliuColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: CaliuColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: CaliuColors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginNotice extends StatelessWidget {
  const _LoginNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CaliuColors.maroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CaliuColors.maroon.withValues(alpha: 0.3)),
      ),
      child: Text(message, style: const TextStyle(color: CaliuColors.maroon)),
    );
  }
}
