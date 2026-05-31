/// The selectable items in the desktop/tablet account left rail. Used by both
/// the rail (to render the active highlight) and the shell.
enum AccountRailItem {
  profile,
  orders,
  returns,
  wallet,
  addresses,
  cards,
  security,
  notifications,
  help,

  /// No rail item active — the bare `/account` welcome panel.
  none,
}

/// Resolves the active rail item from a router location (matchedLocation).
/// Sub-routes inherit their parent's highlight (e.g. `/orders/42` → orders).
AccountRailItem accountRailItemFor(String location) {
  if (location.startsWith('/account/profile')) return AccountRailItem.profile;
  if (location.startsWith('/account/security')) return AccountRailItem.security;
  if (location.startsWith('/account/cards')) return AccountRailItem.cards;
  if (location.startsWith('/account/notifications')) {
    return AccountRailItem.notifications;
  }
  if (location.startsWith('/orders')) return AccountRailItem.orders;
  if (location.startsWith('/returns')) return AccountRailItem.returns;
  if (location.startsWith('/wallet')) return AccountRailItem.wallet;
  if (location.startsWith('/profile/addresses')) {
    return AccountRailItem.addresses;
  }
  if (location.startsWith('/help')) return AccountRailItem.help;
  return AccountRailItem.none;
}
