import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/design/responsive/centered_content_column.dart';
import 'package:mopro/design/responsive/responsive_builder.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/account/widgets/account_left_rail.dart';
import 'package:mopro/features/account/widgets/account_welcome_panel.dart';
import 'package:mopro/features/account/widgets/membership_tier_card.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro_api/mopro_api.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mobile: existing list-then-detail menu, unchanged. Tablet/desktop: the
    // two-pane (rail + welcome panel) rendered inside the AppShell's WebHeader.
    return ResponsiveBuilder(
      mobile: (_) => const _AccountMobileBody(),
      tablet: (_) => const _AccountWidePane(),
      desktop: (_) => const _AccountWidePane(),
    );
  }
}

/// Tablet/desktop `/account` content: sticky rail + welcome panel. Sits inside
/// the AppShell (which already provides the WebHeader + MegaMenuBar), so it adds
/// no top chrome of its own.
class _AccountWidePane extends StatelessWidget {
  const _AccountWidePane();

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= 1024;
    final railWidth = isDesktop ? 260.0 : 240.0;
    final gap = isDesktop ? 32.0 : 24.0;
    return Scaffold(
      body: CenteredContentColumn(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: railWidth,
              child: const SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: AccountLeftRail(),
              ),
            ),
            SizedBox(width: gap),
            const Expanded(
              child: SingleChildScrollView(
                child: AccountWelcomePanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountMobileBody extends ConsumerWidget {
  const _AccountMobileBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final authState = ref.watch(authNotifierProvider).valueOrNull;
    final themeMode = ref.watch(themeControllerProvider);
    final isAuthed = authState is AuthAuthenticated;

    if (!isAuthed) {
      return Scaffold(
        backgroundColor: cs.surfaceContainerHighest,
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _AccountLoggedOutHeader()),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: _GuestMenu(themeMode: themeMode),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      );
    }

    final ordersState = ref.watch(ordersProvider);
    final walletState = ref.watch(walletProvider);
    final plansState = ref.watch(cashbackPlansProvider);

    final activeOrderCount = ordersState.orders.valueOrNull
            ?.where(
              (o) =>
                  o.status != 'delivered' &&
                  o.status != 'cancelled' &&
                  o.status != 'refunded',
            )
            .length ??
        0;

    final balanceMinor = walletState.balance.valueOrNull?.amountMinor ?? 0;

    final activePlanCount = plansState.plans.valueOrNull
            ?.where((p) => p.status == CashbackPlanStatusEnum.active)
            .length ??
        0;

    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      body: CustomScrollView(
        slivers: [
          // ── Orange header (logged-in stats) ──────────────────────────────
          SliverToBoxAdapter(
            child: _AccountHeader(
              activeOrderCount: activeOrderCount,
              balanceMinor: balanceMinor,
              activePlanCount: activePlanCount,
            ),
          ),
          // AC-05: membership-tier badge + progress (derived read-model).
          const SliverToBoxAdapter(child: MembershipTierCard()),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Quick actions row ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: _TileGroup(
              children: [
                _Tile(
                  icon: Icons.shopping_bag_outlined,
                  label: 'account.my_orders'.tr(),
                  onTap: () => context.push('/orders'),
                ),
                _Tile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'account.cashback_wallet'.tr(),
                  onTap: () => context.push('/wallet'),
                ),
                _Tile(
                  icon: Icons.favorite_border_rounded,
                  label: 'nav.favorites'.tr(),
                  onTap: () => context.go('/favorites'),
                ),
                _Tile(
                  icon: Icons.location_on_outlined,
                  label: 'address.list_title'.tr(),
                  onTap: () => context.push('/profile/addresses'),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── My content group (reviews + questions) ──────────────────────
          SliverToBoxAdapter(
            child: _TileGroup(
              children: [
                _Tile(
                  icon: Icons.rate_review_outlined,
                  label: 'account.rail_reviews'.tr(),
                  onTap: () => context.push('/account/reviews'),
                ),
                _Tile(
                  icon: Icons.help_outline_rounded,
                  label: 'account.rail_questions'.tr(),
                  onTap: () => context.push('/account/questions'),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Settings group ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _TileGroup(
              header: 'account.settings_header'.tr(),
              children: [
                _Tile(
                  icon: Icons.person_outline_rounded,
                  label: 'account.profile'.tr(),
                  onTap: () => context.push('/account/profile'),
                ),
                _Tile(
                  icon: Icons.credit_card_outlined,
                  label: 'account.saved_cards'.tr(),
                  onTap: () => context.push('/account/cards'),
                ),
                _Tile(
                  icon: Icons.security_outlined,
                  label: 'account.security'.tr(),
                  onTap: () => context.push('/account/security'),
                ),
                _Tile(
                  icon: Icons.shield_outlined,
                  label: 'account.rail_privacy'.tr(),
                  onTap: () => context.push('/account/privacy'),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Appearance group with theme toggle ──────────────────────────
          SliverToBoxAdapter(
            child: _TileGroup(
              header: 'account.section_appearance'.tr(),
              children: [
                _ThemeTile(themeMode: themeMode),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Logout ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _TileGroup(
              children: [
                _Tile(
                  icon: Icons.logout_rounded,
                  label: 'account.logout'.tr(),
                  iconColor: cs.error,
                  labelColor: cs.error,
                  showChevron: false,
                  onTap: () =>
                      ref.read(authNotifierProvider.notifier).setLoggedOut(),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ── Orange header ───────────────────────────────────────────────────────

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.activeOrderCount,
    required this.balanceMinor,
    required this.activePlanCount,
  });

  final int activeOrderCount;
  final int balanceMinor;
  final int activePlanCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MoproTokens.primaryLight,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(51),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'account.greeting'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      'account.title'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Stats row
          Row(
            children: [
              _HeaderStat(
                value: '$activeOrderCount',
                label: 'account.stat_active_orders'.tr(),
              ),
              _HeaderDivider(),
              _HeaderStat(
                value: MoneyUtils.formatMinor(
                  balanceMinor,
                  currency: 'TRY_COIN',
                ),
                label: 'account.stat_coin'.tr(),
              ),
              _HeaderDivider(),
              _HeaderStat(
                value: '$activePlanCount',
                label: 'account.stat_active_plans'.tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: Colors.white.withAlpha(77),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Tile group (white card) ─────────────────────────────────────────────

class _TileGroup extends StatelessWidget {
  const _TileGroup({required this.children, this.header});
  final List<Widget> children;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Material (not ColoredBox) so the child ListTiles paint their background
    // + ink splashes on this surface instead of being hidden by an opaque box.
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                header!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ...children.map(
            (child) => Column(
              children: [
                child,
                if (child != children.last)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
    this.showChevron = true,
    // ignore: avoid_field_initializers_in_const_classes — fixed null for this variant
  }) : trailing = null;

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;
  final bool showChevron;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? cs.primary).withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: iconColor ?? cs.primary),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w500,
            ),
      ),
      trailing: showChevron
          ? trailing ??
              Icon(
                Icons.chevron_right,
                size: 20,
                color: cs.onSurfaceVariant,
              )
          : trailing,
      onTap: onTap,
    );
  }
}

// ── Theme tile ──────────────────────────────────────────────────────────

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.themeMode});
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    final (icon, label, subLabel) = switch (themeMode) {
      ThemeMode.light => (
          Icons.light_mode_rounded,
          'account.theme_light_title'.tr(),
          'account.theme_active'.tr(),
        ),
      ThemeMode.dark => (
          Icons.dark_mode_rounded,
          'account.theme_dark_title'.tr(),
          'account.theme_active'.tr(),
        ),
      ThemeMode.system => (
          Icons.brightness_auto_rounded,
          'account.theme_system_title'.tr(),
          'account.theme_system_sub'.tr(),
        ),
    };

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: cs.primary),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      subtitle: Text(
        subLabel,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            icon: Icons.light_mode_rounded,
            selected: themeMode == ThemeMode.light,
            onTap: () => ref
                .read(themeControllerProvider.notifier)
                .setMode(ThemeMode.light),
            cs: cs,
            semanticLabel: 'account.theme_light'.tr(),
          ),
          const SizedBox(width: 6),
          _ModeChip(
            icon: Icons.dark_mode_rounded,
            selected: themeMode == ThemeMode.dark,
            onTap: () => ref
                .read(themeControllerProvider.notifier)
                .setMode(ThemeMode.dark),
            cs: cs,
            semanticLabel: 'account.theme_dark'.tr(),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.cs,
    required this.semanticLabel,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        child: GestureDetector(
          onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
        ),
            child: Icon(
              icon,
              size: 16,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Logged-out header (guest mode) ─────────────────────────────────────

class _AccountLoggedOutHeader extends StatelessWidget {
  const _AccountLoggedOutHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MoproTokens.primaryLight,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        bottom: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(51),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'account.guest_greeting'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'account.guest_prompt'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => context.push('/auth/login'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: MoproTokens.primaryLight,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'auth.login'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/auth/register'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'account.menu_register'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Guest menu (public rows + soft-gated rows that open login sheet) ────────

class _GuestMenu extends ConsumerWidget {
  const _GuestMenu({required this.themeMode});
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    void softGated(String reason) {
      showLoginRequiredSheet(context, reason: reason);
    }

    // Material (not ColoredBox) so the child ListTiles paint their background
    // + ink splashes on this surface instead of being hidden by an opaque box.
    return Material(
      color: cs.surface,
      child: Column(
        children: [
          _GuestRow(
            icon: Icons.shopping_bag_outlined,
            label: 'account.orders'.tr(),
            onTap: () => softGated('account.softgate_orders'.tr()),
          ),
          _Sep(),
          _GuestRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'account.wallet'.tr(),
            onTap: () => softGated('account.softgate_wallet'.tr()),
          ),
          _Sep(),
          _GuestRow(
            icon: Icons.favorite_border_rounded,
            label: 'account.menu_favorites'.tr(),
            onTap: () => context.go('/favorites'),
          ),
          _Sep(),
          _GuestRow(
            icon: Icons.location_on_outlined,
            label: 'account.addresses'.tr(),
            onTap: () =>
                softGated('account.softgate_addresses'.tr()),
          ),
          _Sep(),
          _GuestRow(
            icon: Icons.help_outline_rounded,
            label: 'account.menu_help'.tr(),
            onTap: () => context.push('/help'), // AC-02: real /help route (was dead)
          ),
          _Sep(),
          // Theme toggle works for guests too
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.dark_mode_rounded
                    : themeMode == ThemeMode.light
                        ? Icons.light_mode_rounded
                        : Icons.brightness_auto_rounded,
                size: 20,
                color: cs.primary,
              ),
            ),
            title: Text(
              themeMode == ThemeMode.dark
                  ? 'account.theme_dark_title'.tr()
                  : themeMode == ThemeMode.light
                      ? 'account.theme_light_title'.tr()
                      : 'account.theme_system_title'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref
                      .read(themeControllerProvider.notifier)
                      .setMode(ThemeMode.light),
                  icon: Icon(
                    Icons.light_mode_rounded,
                    size: 20,
                    color: themeMode == ThemeMode.light
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref
                      .read(themeControllerProvider.notifier)
                      .setMode(ThemeMode.dark),
                  icon: Icon(
                    Icons.dark_mode_rounded,
                    size: 20,
                    color: themeMode == ThemeMode.dark
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: cs.primary),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
