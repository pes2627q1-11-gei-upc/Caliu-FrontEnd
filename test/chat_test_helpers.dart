import 'package:caliu/data/auth_session.dart';
import 'package:http/http.dart' as http;

/// Sessió en memòria per als tests del xat.
class MemorySession implements AuthSessionStore {
  MemorySession([this.token]);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}

const eventJson = {
  'id': 'evt-1',
  'title': 'Concert al Parc',
  'categories': ['Música'],
  'venue': 'Parc de la Ciutadella',
  'municipality': 'Barcelona',
  'startDate': '2026-11-21T18:00:00.000Z',
};

/// En obrir el xat es recupera l'última conversa (`GET /chat/sessions`,
/// tasca #164). Aquest embolcall hi respon amb un historial buit i passa la
/// resta de peticions a [handler], per als tests que només proven missatges.
Future<http.Response> Function(http.Request) withoutHistory(
  Future<http.Response> Function(http.Request) handler,
) => (request) {
  if (request.method == 'GET' && request.url.path.endsWith('/chat/sessions')) {
    return Future.value(http.Response('{"items":[]}', 200));
  }
  return handler(request);
};
