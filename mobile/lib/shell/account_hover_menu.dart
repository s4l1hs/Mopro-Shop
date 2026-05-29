import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/design/responsive/anchored_overlay_panel.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/account/current_user_provider.dart';

/// Hover-revealed account menu for the WebHeader at `>=600` widths.
///
/// Two variants chosen by [isAuthed]:
/// - **Guest**: login/register CTAs + soft-gated rows (Orders, Favorites, Help).
/// - **Authed**: avatar header + 6 nav rows + logout.
///
/// Session 4b migration: the overlay state machine (hover open/close delays,
/// MouseRegion shared between trigger and panel, Escape close, outside-click
/// dismiss, click-toggle for touch) is now provided by `AnchoredOverlayPanel`.
/// This widget only configures the primitive and renders the variant panel.
class AccountHoverMenu extends ConsumerWidget {
  const AccountHoverMenu({
    required this.trigger,
    required this.isAuthed,
    super.key,
  });

  final Widget trigger;
  final bool isAuthed;

  static const double panelWidth = 280;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnchoredOverlayPanel(
      maxWidth: panelWidth,
      // Right-align the panel to the trigger so the menu drops down beneath
      // the avatar without overflowing the header on the right.
      triggerAnchor: Alignment.bottomRight,
      panelAnchor: Alignment.topRight,
      exclusivityGroup: 'webheader.menus',
      trigger: trigger,
      panelBuilder: (panelContext, close) => _PanelBody(
        isAuthed: isAuthed,
        onDismiss: close,
        onLogout: () {
          ref.read(authNotifierProvider.notifier).setLoggedOut();
          close();
          if (context.mounted) context.go('/');
        },
      ),
    );
  }
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({
    required this.isAuthed,
    required this.onDismiss,
    required this.onLogout,
  });

  final bool isAuthed;
  final VoidCallback onDismiss;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      elevation: 4,
      color: cs.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? MoproTokens.borderDark : MoproTokens.borderLight,
          ),
        ),
        child: FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: isAuthed
                ? _authedChildren(context, onDismiss, onLogout)
                : _guestChildren(context, onDismiss),
          ),
        ),
      ),
    );
  }

  // ── Guest variant ────────────────────────────────────────────────────────

  List<Widget> _guestChildren(BuildContext context, VoidCallback dismiss) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'account.menu_login_prompt'.tr(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                dismiss();
                context.push('/auth/login');
              },
              style: FilledButton.styleFrom(
                backgroundColor: MoproTokens.primaryLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size.fromHeight(40),
              ),
              child: Text('auth.login_title'.tr()),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                dismiss();
                context.push('/auth/register');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: MoproTokens.primaryLight,
                side: const BorderSide(color: MoproTokens.primaryLight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size.fromHeight(40),
              ),
              child: Text('account.menu_register'.tr()),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      _MenuRow(
        icon: Icons.list_alt_outlined,
        label: 'account.orders'.tr(),
        onTap: () {
          dismiss();
          context.go('/orders');
        },
      ),
      _MenuRow(
        icon: Icons.favorite_border_rounded,
        label: 'nav.favorites'.tr(),
        onTap: () {
          dismiss();
          context.go('/favorites');
        },
      ),
      _MenuRow(
        icon: Icons.help_outline_rounded,
        label: 'account.menu_help'.tr(),
        onTap: () {
          dismiss();
          context.go('/account');
        },
      ),
    ];
  }

  // ── Authed variant ───────────────────────────────────────────────────────

  List<Widget> _authedChildren(
    BuildContext context,
    VoidCallback dismiss,
    VoidCallback logout,
  ) {
    final cs = Theme.of(context).colorScheme;
    return [
      // Header strip — name + email pulled from currentUserProvider.
      // Loading / error / null states render the placeholder used in 4a.
      const _AuthedMenuHeader(),
      const Divider(height: 1),
      _MenuRow(
        icon: Icons.person_outline_rounded,
        label: 'account.profile'.tr(),
        onTap: () {
          dismiss();
          context.go('/account/profile');
        },
      ),
      _MenuRow(
        icon: Icons.list_alt_outlined,
        label: 'account.orders'.tr(),
        onTap: () {
          dismiss();
          context.go('/orders');
        },
      ),
      _MenuRow(
        icon: Icons.account_balance_wallet_outlined,
        label: 'account.wallet'.tr(),
        onTap: () {
          dismiss();
          context.go('/wallet');
        },
      ),
      _MenuRow(
        icon: Icons.location_on_outlined,
        label: 'account.addresses'.tr(),
        onTap: () {
          dismiss();
          context.go('/profile/addresses');
        },
      ),
      _MenuRow(
        icon: Icons.credit_card_outlined,
        label: 'account.cards'.tr(),
        onTap: () {
          dismiss();
          context.go('/account/cards');
        },
      ),
      _MenuRow(
        icon: Icons.shield_outlined,
        label: 'account.security'.tr(),
        onTap: () {
          dismiss();
          context.go('/account/security');
        },
      ),
      const Divider(height: 1),
      _MenuRow(
        icon: Icons.logout_rounded,
        label: 'account.logout'.tr(),
        iconColor: cs.error,
        labelColor: cs.error,
        onTap: logout,
      ),
    ];
  }
}

class _AuthedMenuHeader extends ConsumerWidget {
  const _AuthedMenuHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final asyncUser = ref.watch(currentUserProvider);

    final user = asyncUser.valueOrNull;
    final hasUser = user != null;
    final initials = hasUser ? user.initials : 'M';
    final primaryLine = hasUser && user.displayName.isNotEmpty
        ? user.displayName
        : 'account.title'.tr();
    final secondaryLine = hasUser ? user.email : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: MoproTokens.primaryLight,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  primaryLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (secondaryLine != null && secondaryLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondaryLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor ?? cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: labelColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
