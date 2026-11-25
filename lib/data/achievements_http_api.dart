import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'achievements_api.dart';
import 'auth_session.dart';

/// Catàleg d'assoliments contra el backend real (tasca #230), substitueix
/// [MockAchievementsApi]: `GET /achievements` → `{ items: [{ id, title,
/// description, icon, target, progress, unlocked }] }`.
class HttpAchievementsApi implements AchievementsApi {
  HttpAchievementsApi({
    http.Client? client,
    String? baseUrl,
    AuthSessionStore? session,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? apiBaseUrl,
       _session = session ?? AuthSession();

  final http.Client _client;
  final String _baseUrl;
  final AuthSessionStore _session;

  static const _unauthorized = AchievementsApiException(
    'Cal iniciar sessió per veure els teus assoliments',
    statusCode: 401,
  );

  @override
  Future<List<Achievement>> fetchAchievements() async {
    final String? token;
    try {
      token = await _session.readToken();
    } on Exception {
      throw _unauthorized;
    }
    // Sense sessió no cal ni fer la petició.
    if (token == null || token.isEmpty) throw _unauthorized;

    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_baseUrl/achievements'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const AchievementsApiException(
        'No s\'ha pogut connectar amb el servidor. Comprova la connexió i '
        'torna-ho a provar.',
      );
    }

    if (response.statusCode == 401) throw _unauthorized;
    if (response.statusCode != 200) {
      throw AchievementsApiException(
        'No s\'han pogut carregar els assoliments',
        statusCode: response.statusCode,
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const AchievementsApiException(
        'La resposta del servidor no té el format esperat',
      );
    }
    final items = decoded is Map<String, dynamic> ? decoded['items'] : null;
    if (items is! List) {
      throw const AchievementsApiException(
        'La resposta del servidor no té el format esperat',
      );
    }
    return List.unmodifiable(
      items.whereType<Map<String, dynamic>>().map(Achievement.fromJson),
    );
  }
}
