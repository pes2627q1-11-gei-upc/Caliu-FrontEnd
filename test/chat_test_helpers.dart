import 'package:caliu/data/auth_session.dart';

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
