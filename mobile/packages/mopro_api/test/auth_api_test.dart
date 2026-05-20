import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for AuthApi
void main() {
  final instance = MoproApi().getAuthApi();

  group(AuthApi, () {
    // Revoke the provided refresh token
    //
    //Future logout(String xIdempotencyKey, RefreshTokenRequest refreshTokenRequest, { String xTraceId }) async
    test('test logout', () async {
      // TODO
    });

    // Exchange a refresh token for a new token pair
    //
    //Future<TokenPair> refreshToken(String xIdempotencyKey, RefreshTokenRequest refreshTokenRequest, { String xTraceId }) async
    test('test refreshToken', () async {
      // TODO
    });

    // Request a one-time password via SMS
    //
    // Dispatches a 6-digit OTP to the provided phone number. Rate-limited per phone: max 3 requests per 5 minutes. X-Idempotency-Key is NOT honored here — each call always dispatches a new OTP to avoid replay-suppression attacks. 
    //
    //Future requestOtp(RequestOtpRequest requestOtpRequest, { String xTraceId }) async
    test('test requestOtp', () async {
      // TODO
    });

    // Exchange access token + fresh OTP for a step-up token (TTL 5 min)
    //
    // Call this after receiving `403 step_up_required`. The caller must have already called `/v1/auth/otp/request` to obtain a fresh OTP for the currently authenticated phone number. 
    //
    //Future<StepUpTokenResponse> stepUp(String xIdempotencyKey, StepUpRequest stepUpRequest, { String xTraceId }) async
    test('test stepUp', () async {
      // TODO
    });

    // Verify OTP and issue access + refresh token pair
    //
    //Future<TokenPair> verifyOtp(String xIdempotencyKey, VerifyOtpRequest verifyOtpRequest, { String xTraceId }) async
    test('test verifyOtp', () async {
      // TODO
    });

  });
}
