import 'dart:typed_data';

import 'auth_session.dart';
import 'avatar_http_api.dart';

class AvatarApiException implements Exception {
  const AvatarApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Regles del fitxer **original** que tria l'usuari (abans de retallar-lo).
///
/// El que es puja al backend és sempre el retall en PNG de 512×512 de
/// `SquareCropScreen`, que compleix les regles del servidor (JPEG o PNG, fins
/// a 2 MiB) encara que l'original sigui un WebP o pesi més de 2 MiB.
abstract final class AvatarRules {
  /// Mida màxima del fitxer original que tria l'usuari.
  static const maxBytes = 5 * 1024 * 1024;

  static const allowedContentTypes = {'image/jpeg', 'image/png', 'image/webp'};

  static const _extensions = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  /// Tipus MIME a partir del nom del fitxer, o null si no és permès.
  static String? contentTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return null;
    return _extensions[fileName.substring(dot + 1).toLowerCase()];
  }

  /// Missatge d'error si el fitxer no compleix les regles; null si és vàlid.
  static String? validate({required String fileName, required int sizeBytes}) {
    if (contentTypeFor(fileName) == null) {
      return 'Format no permès. Tria una imatge JPG, PNG o WebP.';
    }
    if (sizeBytes > maxBytes) {
      return 'La imatge és massa gran. La mida màxima és de 5 MB.';
    }
    return null;
  }
}

/// Foto de perfil de l'usuari autenticat (H.U #35).
///
/// Endpoints del backend (OpenAPI), vegeu [HttpAvatarApi]:
/// - `PUT /users/me/avatar` (multipart, camp `avatar`, JPEG o PNG fins a
///   2 MiB) → `{ "avatarUrl" }`; substitueix l'anterior. 400 si la imatge no
///   és vàlida, 413 si és massa gran, 401 sense JWT vàlid
/// - `GET /users/me` inclou `avatarUrl`
abstract interface class AvatarApi {
  /// Foto actual, o null si encara no en té.
  Future<Uint8List?> fetchAvatar();

  /// Puja [bytes] (ja retallada en quadrat) i substitueix l'anterior.
  Future<void> uploadAvatar(Uint8List bytes, {required String contentType});
}

/// Instància que fa servir l'app: el backend real (tasca #231).
AvatarApi createAvatarApi({AuthSessionStore? session}) =>
    HttpAvatarApi(session: session);

/// Implementació en memòria, per als tests.
class MockAvatarApi implements AvatarApi {
  MockAvatarApi({
    this.session,
    Uint8List? initial,
    this.latency = const Duration(milliseconds: 500),
  }) : _avatar = initial;

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la pujada (zero als tests).
  final Duration latency;

  Uint8List? _avatar;

  @override
  Future<Uint8List?> fetchAvatar() async {
    await _simulateRequest();
    return _avatar;
  }

  @override
  Future<void> uploadAvatar(
    Uint8List bytes, {
    required String contentType,
  }) async {
    await _simulateRequest();
    if (!AvatarRules.allowedContentTypes.contains(contentType)) {
      throw const AvatarApiException(
        'Format no permès. Tria una imatge JPG, PNG o WebP.',
        statusCode: 400,
      );
    }
    if (bytes.length > AvatarRules.maxBytes) {
      throw const AvatarApiException(
        'La imatge és massa gran. La mida màxima és de 5 MB.',
        statusCode: 413,
      );
    }
    _avatar = bytes;
  }

  Future<void> _simulateRequest() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session == null) return;
    final token = await session.readToken();
    if (token == null || token.isEmpty) {
      throw const AvatarApiException(
        'Cal iniciar sessió per canviar la foto de perfil',
        statusCode: 401,
      );
    }
  }
}
