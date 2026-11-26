import 'package:flutter/material.dart';

import 'data/chat_api.dart';
import 'data/chat_dates.dart';
import 'theme/caliu_colors.dart';

/// Historial de converses amb l'assistent (H.U #48, tasca #164).
///
/// Mostra les converses de l'usuari, de la més recent a la més antiga. En
/// tocar-ne una, la pantalla es tanca i retorna l'id de la sessió perquè el
/// xat la reobri.
class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({
    super.key,
    required this.loadSessions,
    this.currentSessionId,
    this.now,
  });

  /// Normalment `ChatController.loadSessions`.
  final Future<List<ChatSessionSummary>> Function() loadSessions;

  /// Conversa oberta ara mateix al xat (es marca a la llista).
  final String? currentSessionId;

  /// Rellotge injectable per als tests.
  final DateTime Function()? now;

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  List<ChatSessionSummary>? _sessions;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await widget.loadSessions();
      if (!mounted) return;
      setState(() {
        // Les converses sense cap missatge (una "Nova conversa" on no s'ha
        // escrit res) no aporten res a l'historial.
        _sessions = [
          for (final session in sessions)
            if (!session.isEmpty) session,
        ];
        _loading = false;
      });
    } on ChatApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        // Sense sessió, «Torna-ho a provar» no serviria: es torna al xat, que
        // mostra el botó d'iniciar sessió.
        Navigator.of(context).pop();
        return;
      }
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      _showError('S\'ha produït un error inesperat. Torna-ho a provar.');
    }
  }

  void _showError(String message) {
    setState(() {
      _error = message;
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
        title: const Text('Historial de converses'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final sessions = _sessions;
    if (_loading && sessions == null) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }
    if (_error != null && sessions == null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: 'No s\'ha pogut carregar l\'historial',
        text: _error!,
        action: FilledButton(
          onPressed: _load,
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          child: const Text('Torna-ho a provar'),
        ),
      );
    }
    if (sessions == null || sessions.isEmpty) {
      return const _Message(
        icon: Icons.forum_outlined,
        title: 'Encara no tens cap conversa',
        text:
            'Quan facis una pregunta a l\'assistent, la conversa apareixerà '
            'aquí perquè la puguis tornar a obrir.',
      );
    }
    final now = (widget.now ?? DateTime.now)();
    return RefreshIndicator(
      color: CaliuColors.red,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final session = sessions[index];
          final current = session.id == widget.currentSessionId;
          final date = session.lastActivityAt;
          return ListTile(
            key: ValueKey('chat-history-${session.id}'),
            leading: CircleAvatar(
              backgroundColor: current
                  ? CaliuColors.red
                  : CaliuColors.maroon.withValues(alpha: 0.1),
              foregroundColor: current ? Colors.white : CaliuColors.maroon,
              child: const Icon(Icons.chat_bubble_outline, size: 20),
            ),
            title: Text(
              session.title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: CaliuColors.maroonDeep,
              ),
            ),
            subtitle: Text(
              [
                if (date != null)
                  '${chatDayLabel(date, now)} · ${chatTime(date)}',
                if (current) 'Conversa actual',
              ].join(' · '),
            ),
            onTap: () => Navigator.of(context).pop(session.id),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: CaliuColors.maroon),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: CaliuColors.maroonDeep,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CaliuColors.textMuted),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
