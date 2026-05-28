import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/address/providers/addresses_provider.dart';
import 'package:mopro/features/address/widgets/address_card.dart';

class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('address.list_title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/profile/addresses/new'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(addressesProvider.notifier).refresh(),
        child: state.addresses.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) {
            final appError = err is AppError
                ? err
                : UnknownError(statusCode: 0, message: err.toString());
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorBanner(
                error: appError,
                onRetry: () =>
                    ref.read(addressesProvider.notifier).refresh(),
              ),
            );
          },
          data: (addresses) {
            if (addresses.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [EmptyState.empty()],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: addresses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => AddressCard(
                address: addresses[i],
                onEdit: () => context.push(
                  '/profile/addresses/${addresses[i].id}/edit',
                  extra: addresses[i],
                ),
                onDelete: () =>
                    _confirmDelete(context, ref, addresses[i].id),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('address.delete_title'.tr()),
        content: Text('address.delete_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'common.delete'.tr(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(addressesProvider.notifier).deleteAddress(id);
    }
  }
}
