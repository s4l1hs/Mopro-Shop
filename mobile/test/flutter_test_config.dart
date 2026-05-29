import 'dart:async';

import '_support/golden_platform.dart';

/// Global test bootstrap. Installs the Linux/CI golden platform guard (§5.5)
/// for every test in the suite.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  installPlatformGuardedGoldenComparator();
  await testMain();
}
