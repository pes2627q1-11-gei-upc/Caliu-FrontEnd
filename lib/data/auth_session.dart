import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AuthSessionStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> clear();
}

class AuthSession implements AuthSessionStore {
  AuthSession({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clear() => _storage.delete(key: _tokenKey);
}
