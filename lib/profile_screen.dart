import 'package:flutter/material.dart';

import 'config.dart';
import 'data/auth_api.dart';
import 'data/auth_session.dart';
import 'data/events_api.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'theme/caliu_colors.dart';

/// Pestanya Perfil: mostra el compte autenticat i l’estat de connexió de l’API.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final EventsApi _api = EventsApi();
  final AuthApi _authApi = AuthApi();
  final AuthSession _authSession = AuthSession();
  ApiHealth? _health;
  AuthenticatedProfile? _profile;
  String? _token;
  String? _profileError;
  bool _loading = true;
  bool _profileLoading = true;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _check();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    if (mounted) {
      setState(() {
        _profileLoading = true;
        _profileError = null;
      });
    }
    try {
      final token = await _authSession.readToken();
      if (token == null) {
        if (!mounted) return;
        setState(() {
          _token = null;
          _profile = null;
          _profileLoading = false;
        });
        return;
      }
      final profile = await _authApi.fetchProfile(token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _profile = profile;
        _profileLoading = false;
      });
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        await _authSession.clear();
        if (!mounted) return;
        setState(() {
          _token = null;
          _profile = null;
          _profileError = 'La sessió ha caducat. Inicia sessió de nou.';
          _profileLoading = false;
        });
        return;
      }
      setState(() {
        _profileError = error.message;
        _profileLoading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _profileError = 'No s’ha pogut llegir la sessió desada al dispositiu.';
        _profileLoading = false;
      });
    }
  }

  Future<void> _openLogin() async {
    final loggedIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const LoginScreen()));
    if (loggedIn == true) await _loadAccount();
  }

  Future<void> _openRegistration() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RegisterScreen()),
    );
    if (registered == true) await _loadAccount();
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tancar sessió?'),
        content: const Text(
          'Hauràs de tornar a iniciar sessió per accedir a les dades del teu perfil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel·la'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tanca la sessió'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loggingOut = true;
      _profileError = null;
    });

    try {
      await _authSession.clear();
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loggingOut = false;
        _profileError = 'No s’ha pogut esborrar la sessió d’aquest dispositiu.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _token = null;
      _profile = null;
      _profileLoading = true;
    });

    String? notice;
    try {
      await _authApi.logout(token);
    } on AuthApiException {
      notice = 'La sessió s’ha esborrat d’aquest dispositiu, però no s’ha pogut confirmar el tancament amb el servidor.';
    } on Exception {
      notice = 'La sessió s’ha esborrat d’aquest dispositiu, però no s’ha pogut contactar amb el servidor.';
    }

    if (!mounted) return;
    setState(() => _profileLoading = false);
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => LoginScreen(notice: notice)),
    );
    if (loggedIn == true) await _loadAccount();
  }

  Future<void> _editUsername() async {
    final profile = _profile;
    final token = _token;
    if (profile == null || token == null) return;

    final updatedProfile = await showDialog<AuthenticatedProfile>(
      context: context,
      builder: (_) => _EditUsernameDialog(
        username: profile.username,
        onSave: (username) =>
            _authApi.updateProfile(token: token, username: username),
      ),
    );

    if (updatedProfile != null && mounted) {
      setState(() {
        _profile = updatedProfile;
        _profileError = null;
      });
    }
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    final health = await _api.fetchHealth();
    if (!mounted) return;
    setState(() {
      _health = health;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Text('Perfil'),
      ),
      body: RefreshIndicator(
        onRefresh: _check,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _accountCard(context),
            const SizedBox(height: 20),
            Text(
              'Estat del servidor',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: CaliuColors.maroon,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Comprova que el mòbil arriba a l’API ($apiBaseUrl). '
              'Estira cap avall per tornar a provar.',
              style: TextStyle(color: CaliuColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _HealthCard(health: _health!),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _check,
              icon: const Icon(Icons.refresh),
              label: const Text('Tornar a comprovar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(BuildContext context) {
    if (_profileLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final profile = _profile;
    if (profile != null) {
      return Card(
        color: CaliuColors.beigeCard,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: CaliuColors.maroon,
                    foregroundColor: Colors.white,
                    child: Text(
                      profile.username.isEmpty
                          ? '?'
                          : profile.username[0].toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.username,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: CaliuColors.maroon,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          profile.email,
                          style: TextStyle(color: CaliuColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edita el nom d’usuari',
                    onPressed: _editUsername,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                profile.preferences.isEmpty
                    ? 'Encara no tens preferències desades.'
                    : 'Preferències: ${profile.preferences.join(', ')}',
                style: TextStyle(color: CaliuColors.textMuted),
              ),
              if (_profileError case final error?) ...[
                const SizedBox(height: 12),
                Text(error, style: const TextStyle(color: CaliuColors.red)),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loggingOut ? null : _logout,
                icon: _loggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                label: Text(
                  _loggingOut ? 'Tancant sessió…' : 'Tanca la sessió',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: CaliuColors.beigeCard,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Accedeix al teu compte',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: CaliuColors.maroon,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_profileError case final error?) ...[
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(color: CaliuColors.red)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openLogin,
              icon: const Icon(Icons.login),
              label: const Text('Inicia sessió'),
              style: FilledButton.styleFrom(
                backgroundColor: CaliuColors.maroon,
                foregroundColor: Colors.white,
              ),
            ),
            TextButton(
              onPressed: _openRegistration,
              child: const Text('Encara no tens compte? Registra’t'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditUsernameDialog extends StatefulWidget {
  const _EditUsernameDialog({required this.username, required this.onSave});

  final String username;
  final Future<AuthenticatedProfile> Function(String username) onSave;

  @override
  State<_EditUsernameDialog> createState() => _EditUsernameDialogState();
}

class _EditUsernameDialogState extends State<_EditUsernameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.username);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final updated = await widget.onSave(_controller.text);
      if (mounted) Navigator.pop(context, updated);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage =
            'No s’ha pogut actualitzar el perfil. Torna-ho a provar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Canvia el nom d’usuari'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: 30,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _saving ? null : _save(),
              decoration: const InputDecoration(
                labelText: 'Nom d’usuari',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final username = value?.trim() ?? '';
                if (username.isEmpty) {
                  return 'El nom d’usuari és obligatori.';
                }
                if (username.length > 30) return 'Màxim 30 caràcters.';
                return null;
              },
            ),
            if (_errorMessage case final message?) ...[
              const SizedBox(height: 8),
              Text(message, style: const TextStyle(color: CaliuColors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel·la'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Desa'),
        ),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final ApiHealth health;

  @override
  Widget build(BuildContext context) {
    final ok = health.ok;
    final color = ok ? const Color(0xFF2E7D32) : CaliuColors.red;
    final title = ok ? 'Connectat' : 'No es pot connectar';
    final detail = ok
        ? [
            if (health.service != null) health.service!,
            if (health.status != null) 'status: ${health.status}',
          ].join(' · ')
        : (health.error ?? 'Error desconegut');

    return Card(
      color: CaliuColors.beigeCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.error_outline,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: TextStyle(color: CaliuColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SelectableText(
              health.baseUrl,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
