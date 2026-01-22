class ApiPaths {
  ApiPaths._();

  static const authForgotPassword = '/auth/forgot-password';
  static const authResetPassword = '/auth/reset-password';
  static const authRefresh = '/auth/refresh';
  static const authMe = '/auth/me';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';

  static const checkoutCreate = '/api/checkout/create';
  static String courseBundleCheckout(String bundleId) =>
      '/api/course-bundles/$bundleId/checkout-session';

  static const billingCreateSubscription = '/api/billing/create-subscription';
  static const billingCustomerPortal = '/api/billing/customer-portal';
  static const billingSessionStatus = '/api/billing/session-status';
  static const billingCancelSubscription = '/api/billing/cancel-subscription';

  static const meMembership = '/api/me/membership';
  static const meEntitlements = '/api/me/entitlements';
  static const meClaimPurchase = '/api/me/claim-purchase';

  static const orders = '/orders';
  static String order(String orderId) => '/orders/$orderId';

  static const mediaSign = '/media/sign';
  static const mediaUploadUrl = '/api/media/upload-url';
  static const mediaPlaybackUrl = '/api/media/playback-url';
  static const mediaCoverUploadUrl = '/api/media/cover-upload-url';
  static const mediaCoverFromMedia = '/api/media/cover-from-media';
  static const mediaCoverClear = '/api/media/cover-clear';
  static String mediaStatus(String mediaId) => '/api/media/$mediaId';
}
