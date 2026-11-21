import 'package:flutter/material.dart';

import 'data/auth_validators.dart';
import 'data/password_reset_api.dart';
import 'new_password_screen.dart';
import 'theme/caliu_colors.dart';

/// "He oblidat la contrasenya" (tasca #174, H.U #57): demana el correu i
/// envia les instruccions. Retorna `true` si l'usuari ha acabat canviant la
/// contrasenya, perquè el login ho pugui dir.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail, this.api});

  /// Correu que ja havia escrit al login.
  final String? initialEmail;

  /// Per defecte, [createPasswordResetApi].
  final PasswordResetApi? api;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail?.trim() ?? '',
  );
  late final PasswordResetApi _api = widget.api ?? createPasswordResetApi();

  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.requestReset(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sending = false;
      });
    } on PasswordResetException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No s\'ha pogut enviar el correu. Torna-ho a provar.';
        _sending = false;
      });
    }
  }

  Future<void> _openNewPassword() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => NewPasswordScreen(api: _api)),
    );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Text('He oblidat la contrasenya'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [_sent ? _buildSent() : _buildForm()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recupera el teu compte',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: CaliuColors.maroon,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Escriu el correu del teu compte i t\'enviarem un codi per '
            'establir una contrasenya nova.',
            style: TextStyle(color: CaliuColors.textMuted),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              labelText: 'Correu electrònic',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: AuthValidators.email,
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            ResetErrorBox(message: error),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: CaliuColors.maroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Envia les instruccions'),
          ),
          TextButton(
            onPressed: _openNewPassword,
            child: const Text('Ja tinc un codi'),
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: CaliuColors.maroon,
        ),
        const SizedBox(height: 16),
        Text(
          'Revisa el teu correu',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: CaliuColors.maroon,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        // No revela si el compte existeix (H.U #57).
        Text(
          'Si ${_emailController.text.trim()} correspon a un compte de '
          'Caliu, rebràs un correu amb un codi per canviar la contrasenya. '
          'El codi caduca d\'aquí a una estona.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: CaliuColors.textMuted),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _openNewPassword,
          style: FilledButton.styleFrom(
            backgroundColor: CaliuColors.maroon,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: const Text('Introdueix el codi'),
        ),
        TextButton(
          onPressed: () => setState(() => _sent = false),
          child: const Text('No l\'he rebut: torna a enviar'),
        ),
      ],
    );
  }
}

/// Caixa d'error compartida per les pantalles de recuperació.
class ResetErrorBox extends StatelessWidget {
  const ResetErrorBox({super.key, required this.message});

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
