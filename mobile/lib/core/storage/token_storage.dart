import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _keyAccess = 'access_token';
const _keyRefresh = 'refresh_token';
const _keyAccessExpiresAt = 'access_token_expires_at';

class TokenStorage {
  const TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _keyAccess);

  Future<String?> readRefreshToken() => _storage.read(key: _keyRefresh);

  Future<DateTime?> readAccessExpiresAt() async {
    final raw = await _storage.read(key: _keyAccessExpiresAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int accessExpiresIn,
  }) async {
    final expiresAt =
        DateTime.now().add(Duration(seconds: accessExpiresIn)).toUtc();
    await Future.wait([
      _storage.write(key: _keyAccess, value: accessToken),
      _storage.write(key: _keyRefresh, value: refreshToken),
      _storage.write(
          key: _keyAccessExpiresAt, value: expiresAt.toIso8601String(),),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyAccess),
      _storage.delete(key: _keyRefresh),
      _storage.delete(key: _keyAccessExpiresAt),
    ]);
  }
}
