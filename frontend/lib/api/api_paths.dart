class ApiPaths {
  ApiPaths._();

  static const authRequestPasswordReset = '/auth/forgot-password';
  static const authResetPassword = '/auth/reset-password';
  static const authRefresh = '/auth/refresh';
  static const authMe = '/profiles/me';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';
  static const authSendVerification = '/auth/send-verification';
  static const authVerifyEmail = '/auth/verify-email';
  static const authOnboardingCreateProfile =
      '/auth/onboarding/create-profile';
  static const authOnboardingComplete = '/auth/onboarding/complete';
  static const entryState = '/entry-state';

  static const billingCreateSubscription = '/api/billing/create-subscription';
  static const checkoutCreate = '/api/checkout/create';
  static const referralsRedeem = '/referrals/redeem';

  static const mediaPreviews = '/api/lesson-media/previews';
}
