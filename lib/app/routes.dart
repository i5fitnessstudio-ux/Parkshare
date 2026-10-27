/// Central route names for the whole application.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String blueSplash = '/blue-splash';
  static const String onboarding = '/onboarding';
  static const String onboardingIntro = '/onboarding-intro';
  static const String roleSelection = '/role-selection';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String termsConditions = '/terms-conditions';
  static const String privacyPolicy = '/privacy-policy';
  static const String otpVerification = '/otp-verification';
  static const String resetPassword = '/reset-password';

  /// Two-step self-service account deletion, reached from the home menu.
  static const String deleteAccount = '/delete-account';

  static const String ownerDashboard = '/owner-dashboard';
  static const String userHome = '/user-home';

  /// Owner payout / settlement surfaces.
  static const String ownerPayments = '/owner-payments';
  static const String ownerPaymentSetup = '/owner-payment-setup';

  // Phase 2-5 routes
  static const String addParking = '/add-parking';
  static const String parkingDetail = '/parking-detail';
  static const String booking = '/booking';
  static const String payment = '/payment';
  static const String paymentSuccess = '/payment-success';
  static const String codPending = '/cod-pending';

  static const String chat = '/chat';
  static const String vehicleForm = '/vehicle-form';
}

/// Route arguments keys.
class RouteArgs {
  RouteArgs._();

  /// role string for login/register screens: 'owner' | 'user'
  static const String role = 'role';

  /// email + devOtp hint passed between forgot-password screens.
  static const String email = 'email';
  static const String otp = 'otp';
  static const String devOtp = 'devOtp';
  static const String message = 'message';

  /// Confirmed booking handed to PaymentSuccessScreen / CodPendingScreen.
  static const String booking = 'booking';

  /// Owner contact block for the Cash-on-Delivery screen.
  static const String ownerContact = 'ownerContact';
}
