import 'package:flutter/foundation.dart';

import 'avatar_api.dart';

/// Foto de perfil compartida, perquè es vegi igual a tot arreu on surti
/// l'usuari (H.U #35).
class AvatarController extends ChangeNotifier {
  AvatarController(this._api);

  /// Instància de l'app. Els tests n'injecten una de pròpia.
  static final AvatarController shared = AvatarController(createAvatarApi());

  final AvatarApi _api;

  Uint8List? _bytes;
  bool _uploading = false;

  /// Foto actual, o null si encara no en té.
  Uint8List? get bytes => _bytes;

  bool get isUploading => _uploading;

  /// Llegeix la foto del servidor. Si falla, es queda sense foto.
  Future<void> load() async {
    try {
      _bytes = await _api.fetchAvatar();
    } catch (_) {
      _bytes = null;
    }
    notifyListeners();
  }

  /// Puja la foto nova i, si va bé, substitueix la que es mostra. Si falla,
  /// es manté l'anterior i es rellança l'error perquè la UI l'expliqui.
  Future<void> upload(Uint8List bytes, {required String contentType}) async {
    if (_uploading) return;
    _uploading = true;
    notifyListeners();
    try {
      await _api.uploadAvatar(bytes, contentType: contentType);
      _bytes = bytes;
    } finally {
      _uploading = false;
      notifyListeners();
    }
  }

  /// Oblida la foto (en tancar sessió).
  void clear() {
    _bytes = null;
    notifyListeners();
  }
}
