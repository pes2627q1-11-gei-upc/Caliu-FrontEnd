import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';
import 'auth_session.dart';
import 'avatar_api.dart';

/// Foto de perfil contra el backend real (tasca #231), substitueix
/// [MockAvatarApi].
///
/// - `PUT /users/me/avatar` (multipart, camp `avatar`, `image/jpeg` o
///   `image/png`, fins a 2 MiB) → `{ avatarUrl }`
/// - `GET /users/me` → `avatarUrl` (absent si no té foto)
/// - La imatge es baixa d'`avatarUrl` (`/users/{id}/avatar/{version}`)
class HttpAvatarApi implements AvatarApi {
  HttpAvatarApi({
    http.Client? client,
    String? baseUrl,
    AuthSessionStore? session,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? apiBaseUrl,
       _session = session ?? AuthSession();

  final http.Client _client;
  final String _baseUrl;
  final AuthSessionStore _session;

  static const _timeout = Duration(seconds: 30);

  static const _unauthorized = AvatarApiException(
    'Cal iniciar sessió per canviar la foto de perfil',
    statusCode: 401,
  );

  static const _offline = AvatarApiException(
    'No s\'ha pogut connectar amb el servidor. Comprova la connexió i '
    'torna-ho a provar.',
  );

  @override
  Future<Uint8List?> fetchAvatar() async {
    final token = await _readToken();
    final http.Response profile;
    try {
      profile = await _client
          .get(
            Uri.parse('$_baseUrl/users/me'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
    } on Exception {
      throw _offline;
    }
    if (profile.statusCode == 401) throw _unauthorized;
    if (profile.statusCode != 200) {
      throw AvatarApiException(
        'No s\'ha pogut carregar la foto de perfil',
        statusCode: profile.statusCode,
      );
    }
    final url = _avatarUrl(profile.body);
    if (url == null) return null;

    final http.Response image;
    try {
      image = await _client.get(Uri.parse(url)).timeout(_timeout);
    } on Exception {
      throw _offline;
    }
    // 404: la foto s'ha substituït o esborrat; es queda sense foto.
    if (image.statusCode == 404) return null;
    if (image.statusCode != 200) {
      throw AvatarApiException(
        'No s\'ha pogut carregar la foto de perfil',
        statusCode: image.statusCode,
      );
    }
    return image.bodyBytes;
  }

  @override
  Future<void> uploadAvatar(
    Uint8List bytes, {
    required String contentType,
  }) async {
    final token = await _readToken();
    final request =
        http.MultipartRequest('PUT', Uri.parse('$_baseUrl/users/me/avatar'))
          ..headers['authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes(
              'avatar',
              bytes,
              filename: contentType == 'image/png'
                  ? 'avatar.png'
                  : 'avatar.jpg',
              // El backend rebutja la imatge si la part no porta el tipus.
              contentType: MediaType.parse(contentType),
            ),
          );

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on Exception {
      throw _offline;
    }

    switch (response.statusCode) {
      case 200:
        return;
      case 400:
        throw const AvatarApiException(
          'La imatge no és vàlida. Tria una foto JPG o PNG.',
          statusCode: 400,
        );
      case 401:
        throw _unauthorized;
      case 413:
        throw const AvatarApiException(
          'La imatge és massa gran. La mida màxima és de 2 MB.',
          statusCode: 413,
        );
    }
    throw AvatarApiException(
      'No s\'ha pogut pujar la foto',
      statusCode: response.statusCode,
    );
  }

  Future<String> _readToken() async {
    final String? token;
    try {
      token = await _session.readToken();
    } on Exception {
      throw _unauthorized;
    }
    // Sense sessió no cal ni fer la petició.
    if (token == null || token.isEmpty) throw _unauthorized;
    return token;
  }

  /// `avatarUrl` de `GET /users/me`, completat amb el servidor si és relatiu.
  String? _avatarUrl(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const AvatarApiException(
        'La resposta del servidor no té el format esperat',
      );
    }
    final url = decoded is Map<String, dynamic> ? decoded['avatarUrl'] : null;
    if (url is! String || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '$_baseUrl${url.startsWith('/') ? '' : '/'}$url';
  }
}
