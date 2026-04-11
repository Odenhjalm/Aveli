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

  static const mediaPreviews = '/api/lesson-media/previews';
}
