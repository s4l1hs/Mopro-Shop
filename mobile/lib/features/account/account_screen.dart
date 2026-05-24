import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('nav.account'.tr())),
      body: ListView(
        children: [
          // Avatar header
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    'M',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Mopro Kullanıcısı',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _Section(
            title: 'account.orders_section'.tr(),
            items: [
              _NavItem(
                icon: Icons.shopping_bag_outlined,
                label: 'account.my_orders'.tr(),
                onTap: () => context.push('/orders'),
              ),
              _NavItem(
                icon: Icons.account_balance_wallet_outlined,
                label: 'account.cashback_wallet'.tr(),
                onTap: () => context.push('/wallet'),
              ),
            ],
          ),
          _Section(
            title: 'account.settings_section'.tr(),
            items: [
              _NavItem(
                icon: Icons.person_outline,
                label: 'account.profile'.tr(),
                onTap: () => context.push('/account/profile'),
              ),
              _NavItem(
                icon: Icons.location_on_outlined,
                label: 'address.list_title'.tr(),
                onTap: () => context.push('/profile/addresses'),
              ),
              _NavItem(
                icon: Icons.credit_card_outlined,
                label: 'account.saved_cards'.tr(),
                onTap: () => context.push('/account/cards'),
              ),
              _NavItem(
                icon: Icons.security_outlined,
                label: 'account.security'.tr(),
                onTap: () => context.push('/account/security'),
              ),
            ],
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text('account.logout'.tr()),
            onTap: () => ref.read(authNotifierProvider.notifier).setLoggedOut(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});
  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        ...items,
        const Divider(height: 1),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
