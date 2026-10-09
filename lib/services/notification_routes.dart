/// Routes a push notification is allowed to open. Every `route:` value the
/// server sends must be listed here (test/notification_routes_test.dart
/// checks this against the functions/ sources).
const Set<String> notificationRoutes = {
  '/agent_referrals',
  '/referral_center',
  '/profile_accept',
  '/profile_updates',
  '/profile_sharing',
  '/authorization_form',
  '/prospect_contact_request',
  '/update_app',
  '/menu',
  '/agent_menu',
};

bool isKnownNotificationRoute(dynamic route) =>
    notificationRoutes.contains(route?.toString());
