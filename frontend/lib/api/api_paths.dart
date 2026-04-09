class ApiPaths {
  ApiPaths._();

  static const authRequestPasswordReset = '/auth/forgot-password';
  static const authResetPassword = '/auth/reset-password';
  static const authRefresh = '/auth/refresh';
  static const authMe = '/profiles/me';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';
  static const authSendVerification = '/auth/send-verification';
  static const authValidateInvite = '/auth/validate-invite';
  static const authVerifyEmail = '/auth/verify-email';
  static const authOnboardingComplete = '/auth/onboarding/complete';

  static const billingCreateSubscription = '/api/billing/create-subscription';
  static const checkoutCreate = '/api/checkout/create';

  static const mediaUploadUrl = '/api/media/upload-url';
  static const mediaUploadUrlRefresh = '/api/media/upload-url/refresh';
  static const mediaComplete = '/api/media/complete';
  static const mediaUploadUrlComplete = '/api/media/upload-url/complete';
  static const mediaAttach = '/api/media/attach';
  static const mediaPreviews = '/api/lesson-media/previews';
  static const mediaCoverUploadUrl = '/api/media/cover-upload-url';
  static const mediaCoverFromMedia = '/api/media/cover-from-media';
  static const mediaCoverClear = '/api/media/cover-clear';
  static String mediaStatus(String mediaId) => '/api/media/$mediaId';
}
