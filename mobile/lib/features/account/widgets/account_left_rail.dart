import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/widgets/account_rail_item.dart';
import 'package:mopro/features/notifications/widgets/notification_badge.dart';

/// Desktop/tablet account navigation rail: a user card on top (authed/guest
/// variants) and a column of menu rows with route-aware active highlight, hover
/// + focus states, and inline Tema / Dil pickers. Rail clicks use `context.go`
/// (replace) so the shell child swaps without growing the history stack.
class AccountLeftRail extends ConsumerStatefulWidget {
  const AccountLeftRail({super.key});

  @override
  ConsumerState<AccountLeftRail> createState() => _AccountLeftRailState();
}

class _AccountLeftRailState extends ConsumerState<AccountLeftRail> {
  bool _themeExpanded = false;
  bool _langExpanded = false;

  static const Map<String, String> _languageNames = {
    'tr': 'Türkçe',
    'en': 'English',
    'de': 'Deutsch',
    'ar': 'العربية',
  };

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isAuthed = user != null;
    final active = accountRailItemFor(GoRouterState.of(context).matchedLocation);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _UserCard(user: user),
        const SizedBox(height: 8),
        if (isAuthed) ..._authedRows(active) else ..._guestRows(),
      ],
    );
  }

  List<Widget> _authedRows(AccountRailItem active) => [
        _row(AccountRailItem.profile, Icons.person_outline_rounded,
            'account.rail_profile'.tr(), active, '/account/profile',),
        _row(AccountRailItem.orders, Icons.shopping_bag_outlined,
            'account.orders'.tr(), active, '/orders',),
        _row(AccountRailItem.returns, Icons.assignment_return_outlined,
            'account.returns'.tr(), active, '/returns',),
        _row(AccountRailItem.reviews, Icons.rate_review_outlined,
            'account.rail_reviews'.tr(), active, '/account/reviews',),
        _row(AccountRailItem.questions, Icons.help_outline_rounded,
            'account.rail_questions'.tr(), active, '/account/questions',),
        _row(AccountRailItem.wallet, Icons.account_balance_wallet_outlined,
            'account.wallet'.tr(), active, '/wallet',),
        _row(AccountRailItem.addresses, Icons.location_on_outlined,
            'account.addresses'.tr(), active, '/profile/addresses',),
        _row(AccountRailItem.cards, Icons.credit_card_outlined,
            'account.cards'.tr(), active, '/account/cards',),
        _row(AccountRailItem.security, Icons.security_outlined,
            'account.security'.tr(), active, '/account/security',),
        _row(AccountRailItem.notifications, Icons.notifications_outlined,
            'account.notifications'.tr(), active, '/account/notifications',
            withBadge: true,),
        const _RailDivider(),
        _row(AccountRailItem.help, Icons.help_outline_rounded,
            'account.menu_help'.tr(), active, '/help',),
        _themeRow(),
        _langRow(),
        const _RailDivider(),
        _logoutRow(),
      ];

  List<Widget> _guestRows() => [
        _row(AccountRailItem.help, Icons.help_outline_rounded,
            'account.menu_help'.tr(), AccountRailItem.none, '/help',),
        _themeRow(),
        _langRow(),
      ];

  Widget _row(
    AccountRailItem item,
    IconData icon,
    String label,
    AccountRailItem active,
    String route, {
    bool withBadge = false,
  }) {
    return _RailRow(
      icon: icon,
      label: label,
      active: item != AccountRailItem.none && item == active,
      onTap: () => context.go(route),
      withBadge: withBadge,
    );
  }

  Widget _themeRow() {
    final mode = ref.watch(themeControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailRow(
          icon: Icons.brightness_6_outlined,
          label: 'account.theme'.tr(),
          active: false,
          trailing: Icon(
            _themeExpanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
          ),
          onTap: () => setState(() => _themeExpanded = !_themeExpanded),
        ),
        if (_themeExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PickerOption(
                  label: 'account.theme_light'.tr(),
                  selected: mode == ThemeMode.light,
                  onTap: () => ref
                      .read(themeControllerProvider.notifier)
                      .setMode(ThemeMode.light),
                ),
                _PickerOption(
                  label: 'account.theme_dark'.tr(),
                  selected: mode == ThemeMode.dark,
                  onTap: () => ref
                      .read(themeControllerProvider.notifier)
                      .setMode(ThemeMode.dark),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _langRow() {
    final current = context.locale.languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailRow(
          icon: Icons.language_outlined,
          label: 'account.language'.tr(),
          active: false,
          trailing: Icon(
            _langExpanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
          ),
          onTap: () => setState(() => _langExpanded = !_langExpanded),
        ),
        if (_langExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final locale in context.supportedLocales)
                  _PickerOption(
                    label: _languageNames[locale.languageCode] ??
                        locale.languageCode,
                    selected: locale.languageCode == current,
                    onTap: () => context.setLocale(locale),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _logoutRow() {
    final cs = Theme.of(context).colorScheme;
    return _RailRow(
      icon: Icons.logout_rounded,
      label: 'account.logout'.tr(),
      active: false,
      foreground: cs.error,
      onTap: () {
        ref.read(authNotifierProvider.notifier).setLoggedOut();
        context.go('/');
      },
    );
  }
}

// ── User card ────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});
  final CurrentUser? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: user != null ? _authed(theme, user!) : _guest(context, theme),
    );
  }

  Widget _authed(ThemeData theme, CurrentUser u) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: cs.primary,
          backgroundImage:
              (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                  ? NetworkImage(u.avatarUrl!)
                  : null,
          child: (u.avatarUrl == null || u.avatarUrl!.isEmpty)
              ? Text(
                  u.initials,
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                u.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (u.email != null && u.email!.isNotEmpty)
                Text(
                  u.email!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _guest(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'account.menu_login_prompt'.tr(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: FilledButton(
            onPressed: () => context.go('/auth/login'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            child: Text('auth.login'.tr()),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: OutlinedButton(
            onPressed: () => context.go('/auth/register'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              side: BorderSide(color: cs.primary),
            ),
            child: Text('account.menu_register'.tr()),
          ),
        ),
      ],
    );
  }
}

// ── Menu row ───────────────────────────────────────────────────────────────

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.trailing,
    this.foreground,
    this.withBadge = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? foreground;
  final bool withBadge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = foreground ?? (active ? cs.primary : cs.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          hoverColor: cs.surfaceContainerHighest,
          focusColor: cs.primary.withValues(alpha: 0.12),
          child: Stack(
            children: [
              // Active left bar.
              if (active)
                Positioned(
                  left: 0,
                  top: 6,
                  bottom: 6,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: MoproTokens.primaryLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      if (withBadge)
                        NotificationBadge(child: Icon(icon, size: 20, color: fg))
                      else
                        Icon(icon, size: 20, color: fg),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: fg,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1));
}
