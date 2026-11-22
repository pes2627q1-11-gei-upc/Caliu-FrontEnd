import 'package:caliu/data/chat_controller.dart';
import 'package:caliu/data/chat_demo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final api = DemoChatApi(latency: Duration.zero);

  test('per defecte el mode demo està apagat', () {
    expect(chatDemoMode, isFalse);
  });

  test('una pregunta normal retorna targetes i filtres', () async {
    final reply = await api.sendMessage(
      token: 'demo',
      message: 'Què puc fer avui a Barcelona?',
    );

    expect(reply.plan, isNull);
    expect(reply.events, hasLength(2));
    expect(reply.events.every((e) => reply.reply.contains(e.title)), isTrue);
    expect(reply.filters?.municipality, 'Barcelona');
    expect(reply.filters?.maxPrice, 0);
  });

  test('demanar un itinerari retorna un pla de 3 passos', () async {
    final reply = await api.sendMessage(
      token: 'demo',
      message: 'Fes-me un itinerari per Girona',
    );

    expect(reply.plan?.steps.map((s) => s.order), [1, 2, 3]);
    expect(reply.plan?.directionsUri, isNotNull);
    expect(reply.events, isEmpty);
  });

  test('"plans amb nens" no es confon amb un itinerari', () async {
    final reply = await api.sendMessage(
      token: 'demo',
      message: 'Plans amb nens aquest cap de setmana',
    );
    expect(reply.plan, isNull);
  });

  test('amb la sessió demo, el xat funciona sense iniciar sessió', () async {
    final chat = ChatController(api: api, session: DemoChatSession());
    addTearDown(chat.dispose);

    await chat.checkSession();
    expect(chat.needsLogin, isFalse);

    await chat.send('Una ruta per avui');
    expect(chat.messages.last.plan, isNotNull);
  });
}
