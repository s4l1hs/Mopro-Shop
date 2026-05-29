import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/design/tokens.dart';

/// Hover-revealed account menu for the WebHeader at `>=600` widths.
///
/// Two variants chosen by [isAuthed]:
/// - **Guest**: login/register CTAs + soft-gated rows (Orders, Favorites, Help).
/// - **Authed**: avatar header + 6 nav rows + logout.
///
/// Hover open delay 80ms, close delay 150ms. Click-toggle for touch web.
/// Escape closes; the panel stays open while the cursor is over either the
/// trigger OR the panel itself (separate `MouseRegion` listeners on both).
class AccountHoverMenu extends ConsumerStatefulWidget {
  const AccountHoverMenu({
    required this.trigger,
    required this.isAuthed,
    super.key,
  });

  final Widget trigger;
  final bool isAuthed;

  static const double panelWidth = 280;
  static const Duration openDelay = Duration(milliseconds: 80);
  static const Duration closeDelay = Duration(milliseconds: 150);

  @override
  ConsumerState<AccountHoverMenu> createState() => _AccountHoverMenuState();
}

class _AccountHoverMenuState extends ConsumerState<AccountHoverMenu> {
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();
  final _focusNode = FocusNode();
  bool _hoveringTrigger = false;
  bool _hoveringPanel = false;
  bool _focused = false;
  Timer? _openTimer;
  Timer? _closeTimer;

  bool get _shouldOpen => _hoveringTrigger || _hoveringPanel || _focused;

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _checkState() {
    final wantOpen = _shouldOpen;
    final isOpen = _overlayController.isShowing;
    if (wantOpen && !isOpen) {
      _closeTimer?.cancel();
      _openTimer?.cancel();
      _openTimer = Timer(AccountHoverMenu.openDelay, () {
        if (mounted && _shouldOpen) _overlayController.show();
      });
    } else if (!wantOpen && isOpen) {
      _openTimer?.cancel();
      _closeTimer?.cancel();
      _closeTimer = Timer(AccountHoverMenu.closeDelay, () {
        if (mounted && !_shouldOpen) _overlayController.hide();
      });
    }
  }

  void _toggle() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    } else {
      _overlayController.show();
      // Move focus into the trigger so the Escape shortcut is in scope.
      _focusNode.requestFocus();
    }
  }

  void _dismiss() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _overlayController.hide();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _DismissIntent: CallbackAction<_DismissIntent>(
              onInvoke: (_) {
                _dismiss();
                return null;
              },
            ),
          },
          child: OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: (overlayContext) {
              return _Panel(
                layerLink: _layerLink,
                isAuthed: widget.isAuthed,
                onDismiss: _dismiss,
                onPanelEnter: () {
                  _hoveringPanel = true;
                  _checkState();
                },
                onPanelExit: () {
                  _hoveringPanel = false;
                  _checkState();
                },
                onLogout: () {
                  ref
                      .read(authNotifierProvider.notifier)
                      .setLoggedOut();
                  _dismiss();
                  if (context.mounted) context.go('/');
                },
              );
            },
            child: MouseRegion(
              onEnter: (_) {
                _hoveringTrigger = true;
                _checkState();
              },
              onExit: (_) {
                _hoveringTrigger = false;
                _checkState();
              },
              child: Focus(
                focusNode: _focusNode,
                onFocusChange: (f) {
                  _focused = f;
                  _checkState();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: widget.trigger,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.layerLink,
    required this.isAuthed,
    required this.onDismiss,
    required this.onPanelEnter,
    required this.onPanelExit,
    required this.onLogout,
  });

  final LayerLink layerLink;
  final bool isAuthed;
  final VoidCallback onDismiss;
  final VoidCallback onPanelEnter;
  final VoidCallback onPanelExit;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Outside-click dismisser.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        // The panel itself, anchored beneath the trigger.
        Positioned(
          width: AccountHoverMenu.panelWidth,
          child: CompositedTransformFollower(
            link: layerLink,
            showWhenUnlinked: false,
            // Drop beneath a 44dp trigger with 6dp breathing room.
            offset: const Offset(
              // Right-align: shift left so panel right edge lines up with
              // trigger right edge (which is 44dp wide).
              -(AccountHoverMenu.panelWidth - 44),
              50,
            ),
            child: MouseRegion(
              onEnter: (_) => onPanelEnter(),
              onExit: (_) => onPanelExit(),
              child: _PanelBody(
                isAuthed: isAuthed,
                onDismiss: onDismiss,
                onLogout: onLogout,
              ),
            ),
          ),
        ),
      ],
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
      // Header strip with placeholder name — user info wiring deferred.
      Padding(
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
              child: const Text(
                'M',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'account.title'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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
