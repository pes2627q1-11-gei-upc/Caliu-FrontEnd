import 'package:flutter/material.dart';

import 'config.dart';
import 'data/events_api.dart';
import 'theme/caliu_colors.dart';

/// Pestanya Perfil: ara mateix mostra l’estat de connexió amb l’API.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final EventsApi _api = EventsApi();
  ApiHealth? _health;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _check();
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
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
