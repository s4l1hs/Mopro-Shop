import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

// Lightweight auth state: true = has a stored access token.
final authStateProvider = FutureProvider.autoDispose<bool>((ref) async {
  final storage = ref.watch(tokenStorageProvider);
  final token = await storage.readAccessToken();
  return token != null;
});
