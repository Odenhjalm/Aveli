class ApiPaths {
  ApiPaths._();

  static const authRequestPasswordReset = '/auth/request-password-reset';
  static const authResetPassword = '/auth/reset-password';
  static const authRefresh = '/auth/refresh';
  static const authMe = '/auth/me';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';
  static const authSendVerification = '/auth/send-verification';
  static const authValidateInvite = '/auth/validate-invite';
  static const authVerifyEmail = '/auth/verify-email';

  static const billingCustomerPortal = '/api/billing/customer-portal';
  static const billingSessionStatus = '/api/billing/session-status';
  static const billingCancelSubscription = '/api/billing/cancel-subscription';

  static const meClaimPurchase = '/api/me/claim-purchase';
  static const meWelcomeComplete = '/api/me/onboarding/welcome-complete';

  static const orders = '/orders';
  static String order(String orderId) => '/orders/$orderId';

  static const mediaSign = '/api/media/sign';
  static const mediaUploadUrl = '/api/media/upload-url';
  static const mediaUploadUrlRefresh = '/api/media/upload-url/refresh';
  static const mediaComplete = '/api/media/complete';
  static const mediaUploadUrlComplete = '/api/media/upload-url/complete';
  static const mediaAttach = '/api/media/attach';
  static const mediaPlaybackUrl = '/api/media/playback-url';
  static const mediaRuntimePlayback = '/api/media/playback';
  static const mediaPreviews = '/api/lesson-media/previews';
  static const mediaLessonPlaybackUrl = '/api/playback/lesson';
  static const mediaCoverUploadUrl = '/api/media/cover-upload-url';
  static const mediaCoverFromMedia = '/api/media/cover-from-media';
  static const mediaCoverClear = '/api/media/cover-clear';
  static String mediaStatus(String mediaId) => '/api/media/$mediaId';
}
