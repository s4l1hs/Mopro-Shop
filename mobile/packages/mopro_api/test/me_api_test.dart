import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for MeApi
void main() {
  final instance = MoproApi().getMeApi();

  group(MeApi, () {
    // Soft-delete the authenticated user account (KVKK / GDPR)
    //
    // Requires step-up authentication (`stepUpAuth` security scheme). Account enters a 30-day grace period before permanent deletion. All active cashback plans are cancelled on confirmation. 
    //
    //Future deleteMe(String xIdempotencyKey, DeleteMeRequest deleteMeRequest, { String xTraceId }) async
    test('test deleteMe', () async {
      // TODO
    });

    // Get authenticated user profile
    //
    //Future<User> getMe({ String xTraceId }) async
    test('test getMe', () async {
      // TODO
    });

    // Register a device FCM token for push notifications
    //
    //Future<Device> registerDevice(String xIdempotencyKey, RegisterDeviceRequest registerDeviceRequest, { String xTraceId }) async
    test('test registerDevice', () async {
      // TODO
    });

    // Remove a registered device (deregister push notifications)
    //
    //Future unregisterDevice(String xIdempotencyKey, int id, { String xTraceId }) async
    test('test unregisterDevice', () async {
      // TODO
    });

    // Update user profile fields
    //
    //Future<User> updateMe(String xIdempotencyKey, UpdateMeRequest updateMeRequest, { String xTraceId }) async
    test('test updateMe', () async {
      // TODO
    });

  });
}
