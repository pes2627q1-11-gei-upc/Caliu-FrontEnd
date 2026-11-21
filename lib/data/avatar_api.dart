import 'dart:typed_data';

import 'auth_session.dart';

class AvatarApiException implements Exception {
  const AvatarApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Regles de la foto de perfil. La H.U #35 deixa la mida i els tipus a
/// confirmar per l'equip: aquests valors són una proposta.
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
/// El backend encara no l'exposa (tasques #148 i #149). Proposta de contracte
/// (pendent de confirmar a l'OpenAPI del backend):
/// - `PUT /users/me/avatar` (multipart, camp `avatar`) → `{ "avatarUrl" }`;
///   substitueix l'anterior. 400 si el tipus no és permès, 413 si és massa
///   gran, 401 sense JWT vàlid
/// - `GET /users/me` inclou `avatarUrl`
abstract interface class AvatarApi {
  /// Foto actual, o null si encara no en té.
  Future<Uint8List?> fetchAvatar();

  /// Puja [bytes] (ja retallada en quadrat) i substitueix l'anterior.
  Future<void> uploadAvatar(Uint8List bytes, {required String contentType});
}

/// Instància que fa servir l'app. Quan el backend estigui llest, aquí es
/// canviarà la implementació simulada per la HTTP.
AvatarApi createAvatarApi({AuthSessionStore? session}) =>
    MockAvatarApi(session: session ?? AuthSession());

/// Implementació en memòria mentre no hi ha backend.
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
