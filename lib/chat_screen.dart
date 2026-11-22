import 'package:flutter/material.dart';

import 'data/chat_api.dart';
import 'data/chat_controller.dart';
import 'data/chat_demo.dart';
import 'data/event.dart';
import 'event_detail_screen.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/chat/chat_bubble.dart';
import 'widgets/chat/typing_indicator.dart';

/// Pantalla de l'assistent de Caliu (H.U #11, tasques #131 i #134).
///
/// Només pinta l'estat de [ChatController]; tota la lògica és al controlador.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.controller,
    this.isActive = true,
    this.openEvent,
    this.openLogin,
  });

  /// Injectable per als tests; per defecte se'n crea un.
  final ChatController? controller;

  /// Si la pestanya Xat és la visible: en tornar-hi es revisa la sessió
  /// (p. ex. si s'ha iniciat sessió des de Perfil).
  final bool isActive;

  /// Com obrir la fitxa d'un esdeveniment. Per defecte, `EventDetailScreen`.
  final void Function(BuildContext context, Event event)? openEvent;

  /// Com obrir el login. Per defecte, `LoginScreen` (retorna true si s'entra).
  final Future<bool?> Function(BuildContext context)? openLogin;

  static const suggestions = [
    'Què puc fer avui a Barcelona?',
    'Plans amb nens aquest cap de setmana',
    'Concerts gratuïts aquesta setmana',
  ];

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _chat = widget.controller ?? ChatController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _chat.checkSession();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _chat.checkSession();
  }

  @override
  void dispose() {
    if (widget.controller == null) _chat.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final value = text ?? _input.text;
    if (value.trim().isEmpty || _chat.isTyping) return;
    _input.clear();
    await _chat.send(value);
  }

  void _openEvent(Event event) {
    final open = widget.openEvent;
    if (open != null) {
      open(context, event);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EventDetailScreen(eventId: event.id, initialEvent: event),
      ),
    );
  }

  Future<void> _login() async {
    final open =
        widget.openLogin ??
        (context) => Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const LoginScreen()),
        );
    final loggedIn = await open(context);
    if (loggedIn == true && mounted) await _chat.checkSession();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20),
            SizedBox(width: 8),
            Text('Assistent Caliu'),
            // Respostes d'exemple sense backend (--dart-define=CHAT_DEMO=true).
            if (chatDemoMode) ...[
              SizedBox(width: 8),
              Text('· demo', style: TextStyle(fontSize: 14)),
            ],
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _chat,
        builder: (context, _) {
          if (_chat.checkingSession) {
            return const Center(
              child: CircularProgressIndicator(color: CaliuColors.red),
            );
          }
          if (_chat.needsLogin && _chat.messages.isEmpty) {
            return _LoginPrompt(onLogin: _login);
          }
          return Column(
            children: [
              Expanded(
                child: _chat.messages.isEmpty
                    ? _EmptyState(onSuggestion: _send)
                    : _MessageList(chat: _chat, onOpenEvent: _openEvent),
              ),
              if (_chat.error != null)
                _ErrorBanner(
                  message: _chat.error!,
                  onClose: _chat.dismissError,
                  onLogin: _chat.needsLogin ? _login : null,
                ),
              _InputBar(
                controller: _input,
                focusNode: _focus,
                enabled: !_chat.needsLogin,
                busy: _chat.isTyping,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.chat, required this.onOpenEvent});

  final ChatController chat;
  final ValueChanged<Event> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final messages = chat.messages;
    final typing = chat.isTyping ? 1 : 0;
    // `reverse`: l'últim missatge queda a baix i la llista hi baixa sola.
    return ListView.builder(
      key: const ValueKey('chat-messages'),
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: messages.length + typing,
      itemBuilder: (context, index) {
        if (typing == 1 && index == 0) {
          return const TypingIndicator(key: ValueKey('chat-typing'));
        }
        final message = messages[messages.length - 1 - (index - typing)];
        return ChatBubble(
          key: ValueKey('chat-message-${message.id}'),
          message: message,
          onOpenEvent: onOpenEvent,
          onRetry: chat.isTyping ? null : () => chat.retry(message.id),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSuggestion});

  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.auto_awesome, size: 48, color: CaliuColors.red),
          const SizedBox(height: 12),
          const Text(
            'Hola! Sóc l\'assistent de Caliu',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: CaliuColors.maroonDeep,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pregunta\'m què fer, on i quan, i et proposaré plans culturals.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CaliuColors.textMuted),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in ChatScreen.suggestions)
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () => onSuggestion(suggestion),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: CaliuColors.maroon.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: CaliuColors.maroon),
            const SizedBox(height: 12),
            const Text(
              'Inicia sessió per parlar amb l\'assistent',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: CaliuColors.maroonDeep,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onLogin,
              style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
              child: const Text('Inicia sessió'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onClose,
    this.onLogin,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CaliuColors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: CaliuColors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: CaliuColors.red, fontSize: 13),
              ),
            ),
            if (onLogin != null)
              TextButton(
                onPressed: onLogin,
                child: const Text('Inicia sessió'),
              ),
            IconButton(
              tooltip: 'Tancar',
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool busy;
  final Future<void> Function([String? text]) onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = enabled && !busy && value.text.trim().isNotEmpty;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat-input'),
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ChatApi.maxMessageLength,
                      // Comptador només quan s'acosta al límit.
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => currentLength > 400
                          ? Text('$currentLength/$maxLength')
                          : null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: canSend ? (_) => onSend() : null,
                      decoration: InputDecoration(
                        hintText: 'Pregunta què fer, on i quan…',
                        filled: true,
                        fillColor: CaliuColors.beige,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    key: const ValueKey('chat-send'),
                    tooltip: 'Enviar',
                    onPressed: canSend ? () => onSend() : null,
                    style: IconButton.styleFrom(
                      backgroundColor: CaliuColors.red,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.send),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
