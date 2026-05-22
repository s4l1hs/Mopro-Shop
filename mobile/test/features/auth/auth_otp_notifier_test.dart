import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/auth/auth_otp_notifier.dart';

void main() {
  test(
    'build completes without StateError — initial resendCountdown is 60',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // listen() keeps the autoDispose provider alive and exercises the
      // real build() — unlike the widget tests which stub the notifier.
      final sub = container.listen(
        authOtpNotifierProvider('+905001234567'),
        (_, __) {},
      );
      addTearDown(sub.close);

      expect(
        container
            .read(authOtpNotifierProvider('+905001234567'))
            .resendCountdown,
        60,
      );

      // Flush the Future.microtask(_startResendCountdown) scheduled in
      // build(). Confirms _startResendCountdown runs without StateError.
      await Future<void>.delayed(Duration.zero);

      expect(
        container
            .read(authOtpNotifierProvider('+905001234567'))
            .resendCountdown,
        60,
      );
    },
  );
}
