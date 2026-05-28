import 'package:dio/dio.dart';

// LoginResult mirrors the server's login response.
class LoginResult {

  const LoginResult({
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.mfaToken,
    this.maskedPhone,
  });
  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? mfaToken;
  final String? maskedPhone;

  bool get requiresMFA => mfaToken != null && mfaToken!.isNotEmpty;
}

/// Handwritten Dio-based client for the email-auth + MFA endpoints.
/// These endpoints were added after the OpenAPI codegen snapshot.
class AuthApiExt {
  AuthApiExt(this._dio);
  final Dio _dio;

  Future<void> register({
    required String email,
    required String password,
    required String nameFirst,
    required String nameLast,
    String locale = 'tr-TR',
  }) async {
    await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'name_first': nameFirst,
      'name_last': nameLast,
      'locale': locale,
    },);
  }

  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final resp = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    },);
    final data = resp.data as Map<String, dynamic>;
    if (data['mfa_required'] == true) {
      return LoginResult(
        mfaToken: data['mfa_token'] as String?,
        maskedPhone: data['masked_phone'] as String?,
      );
    }
    return LoginResult(
      accessToken: data['access_token'] as String?,
      refreshToken: data['refresh_token'] as String?,
      expiresIn: data['expires_in'] as int?,
    );
  }

  Future<LoginResult> verifyEmail({
    required String email,
    required String code,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/auth/verify-email',
      data: {'email': email, 'code': code},
    );
    final data = resp.data!;
    return LoginResult(
      accessToken: data['access_token'] as String?,
      refreshToken: data['refresh_token'] as String?,
      expiresIn: data['expires_in'] as int?,
    );
  }

  Future<void> resendVerification({required String email}) async {
    await _dio.post<void>(
      '/auth/resend-verification',
      data: {'email': email},
    );
  }

  Future<void> forgotPassword({required String email}) async {
    await _dio.post('/auth/forgot-password', data: {'email': email});
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _dio.post('/auth/reset-password', data: {
      'token': token,
      'new_password': newPassword,
    },);
  }

  Future<LoginResult> verifyMFA({
    required String mfaToken,
    required String code,
  }) async {
    final resp = await _dio.post('/auth/mfa/verify', data: {
      'mfa_token': mfaToken,
      'code': code,
    },);
    final data = resp.data as Map<String, dynamic>;
    return LoginResult(
      accessToken: data['access_token'] as String?,
      refreshToken: data['refresh_token'] as String?,
      expiresIn: data['expires_in'] as int?,
    );
  }

  Future<void> enrollMFA({required String phone}) async {
    await _dio.post('/auth/mfa/enroll', data: {'phone': phone});
  }

  Future<void> confirmMFAEnroll({
    required String phone,
    required String code,
  }) async {
    await _dio.post('/auth/mfa/confirm', data: {'phone': phone, 'code': code});
  }

  Future<void> disableMFA() async {
    await _dio.delete('/auth/mfa');
  }
}
