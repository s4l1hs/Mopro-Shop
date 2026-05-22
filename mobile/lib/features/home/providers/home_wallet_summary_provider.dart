import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro_api/mopro_api.dart';

final homeWalletSummaryProvider =
    FutureProvider.autoDispose<WalletBalance>((ref) async {
  final resp = await ref.watch(walletApiProvider).getWalletBalance();
  return resp.data!;
});
