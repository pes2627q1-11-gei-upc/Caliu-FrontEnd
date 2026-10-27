import 'package:flutter/material.dart';

import 'data/auth_api.dart';
import 'data/auth_session.dart';
import 'data/auth_validators.dart';
import 'theme/caliu_colors.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.authApi, this.authSession});

  final AuthApi? authApi;
  final AuthSessionStore? authSession;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  late final AuthApi _authApi = widget.authApi ?? AuthApi();
  late final AuthSessionStore _authSession =
      widget.authSession ?? AuthSession();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await _authApi.register(
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      await _authSession.saveToken(result.token);
      if (mounted) Navigator.of(context).pop(true);
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
            'El compte s’ha creat, però no s’ha pogut desar la sessió de forma segura. Inicia sessió per continuar.';
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
        title: const Text('Crear compte'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [_registrationForm(context)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _registrationForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Uneix-te a Caliu',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: CaliuColors.maroon,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea el teu compte per accedir a les funcionalitats personalitzades.',
            style: TextStyle(color: CaliuColors.textMuted),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nom d’usuari',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            validator: AuthValidators.username,
          ),
          const SizedBox(height: 12),
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
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Contrasenya',
              helperText:
                  'Mínim 8 caràcters Unicode i màxim 72 bytes UTF-8.',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? 'Mostra la contrasenya'
                    : 'Amaga la contrasenya',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            validator: AuthValidators.password,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmationController,
            obscureText: _obscureConfirmation,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _isSubmitting ? null : _register(),
            decoration: InputDecoration(
              labelText: 'Repeteix la contrasenya',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureConfirmation
                    ? 'Mostra la contrasenya'
                    : 'Amaga la contrasenya',
                onPressed: () => setState(
                  () => _obscureConfirmation = !_obscureConfirmation,
                ),
                icon: Icon(
                  _obscureConfirmation
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
            validator: (value) => AuthValidators.passwordConfirmation(
              value,
              _passwordController.text,
            ),
          ),
          if (_errorMessage case final message?) ...[
            const SizedBox(height: 16),
            _RegistrationError(message: message),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _register,
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
                : const Text('Crear compte'),
          ),
        ],
      ),
    );
  }
}

class _RegistrationError extends StatelessWidget {
  const _RegistrationError({required this.message});

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
