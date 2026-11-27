import 'package:flutter/material.dart';

import 'data/auth_validators.dart';
import 'data/password_reset_api.dart';
import 'forgot_password_screen.dart';
import 'theme/caliu_colors.dart';

/// "Nova contrasenya" (tasca #174, H.U #57): el codi rebut per correu i la
/// contrasenya nova, dues vegades. Retorna `true` si s'ha canviat.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, this.initialToken, this.api});

  /// Codi que ja ve donat (p. ex. si en un futur s'obre des de l'enllaç del
  /// correu).
  final String? initialToken;

  /// Per defecte, [createPasswordResetApi].
  final PasswordResetApi? api;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _tokenController = TextEditingController(
    text: widget.initialToken ?? '',
  );
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  late final PasswordResetApi _api = widget.api ?? createPasswordResetApi();

  bool _saving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.resetPassword(
        token: _tokenController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PasswordResetException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No s\'ha pogut canviar la contrasenya. Torna-ho a provar.';
        _saving = false;
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
        title: const Text('Nova contrasenya'),
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
                      const Text(
                        'Escriu el codi que t\'hem enviat per correu i la '
                        'contrasenya nova.',
                        style: TextStyle(color: CaliuColors.textMuted),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _tokenController,
                        textInputAction: TextInputAction.next,
                        // El codi del correu és en minúscules: no forcem
                        // majúscules ni correccions automàtiques.
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Codi del correu',
                          prefixIcon: Icon(Icons.key_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Escriu el codi del correu.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Contrasenya nova',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Mostra la contrasenya'
                                : 'Amaga la contrasenya',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: AuthValidators.password,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          labelText: 'Repeteix la contrasenya nova',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            AuthValidators.passwordConfirmation(
                              value,
                              _passwordController.text,
                            ),
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: 16),
                        ResetErrorBox(message: error),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: CaliuColors.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Canvia la contrasenya'),
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
