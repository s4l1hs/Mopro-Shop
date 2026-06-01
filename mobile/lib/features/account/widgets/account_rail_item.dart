/// The selectable items in the desktop/tablet account left rail. Used by both
/// the rail (to render the active highlight) and the shell.
enum AccountRailItem {
  profile,
  orders,
  returns,
  reviews,
  questions,
  wallet,
  addresses,
  cards,
  security,
  privacy,
  history,
  seller,
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
  if (location.startsWith('/account/privacy')) return AccountRailItem.privacy;
  if (location.startsWith('/account/browsing-history')) {
    return AccountRailItem.history;
  }
  // `/seller/*` (panel); NOT `/sellers/*` (public storefront).
  if (location.startsWith('/seller/')) return AccountRailItem.seller;
  if (location.startsWith('/account/notifications')) {
    return AccountRailItem.notifications;
  }
  if (location.startsWith('/account/reviews')) return AccountRailItem.reviews;
  if (location.startsWith('/account/questions')) {
    return AccountRailItem.questions;
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
