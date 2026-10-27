/// Central user-facing strings. Keep copy consistent with the app design.
class AppStrings {
  AppStrings._();

  static const String appName = 'ParkShare';
  static const String tagline = 'Find · Book · Share parking';

  // Splash
  static const String splashLoading = 'Loading ParkShare…';

  // Onboarding
  static const String onboardTitle1 = 'Find parking near you';
  static const String onboardBody1 =
      'See real parking spaces around your location and pick the best spot.';
  static const String onboardTitle2 = 'Check if your vehicle fits';
  static const String onboardBody2 =
      'Compare your vehicle dimensions with the parking space before booking.';
  static const String onboardTitle3 = 'Share parking and earn';
  static const String onboardBody3 =
      'List your parking space and earn from users who need it.';
  static const String skip = 'Skip';
  static const String next = 'Next';
  static const String getStarted = 'Get Started';

  // Role selection
  static const String chooseYourRole = 'What best describes you?';
  static const String roleOwnerTitle = 'Parking Owner';
  static const String roleOwnerSubtitle = 'List your parking space and earn';
  static const String roleUserTitle = 'Vehicle User';
  static const String roleUserSubtitle = 'Find and book parking near you';

  // Auth
  static const String login = 'Login';
  static const String register = 'Register';
  static const String logout = 'Logout';
  static const String email = 'Email';
  static const String emailHint = 'you@example.com';
  static const String password = 'Password';
  static const String passwordHint = 'At least 6 characters';
  static const String confirmPassword = 'Confirm Password';
  static const String name = 'Full Name';
  static const String phone = 'Phone Number';
  /// Kept for the recovery flow, which is still routed (AppRoutes
  /// .forgotPassword) but is no longer offered as a login-screen link.
  static const String forgotPassword = 'Forgot password?';

  // ---- Legal consent (Terms & Conditions / Privacy Policy) ----
  static const String consentRequired =
      'Please agree to the Terms & Conditions and the Privacy Policy to '
      'create your account.';
  static const String termsConditionsTitle = 'Terms & Conditions';
  static const String privacyPolicyTitle = 'Privacy Policy';
  static const String newHere = 'New here?';
  static const String createAccount = 'Create Account';
  static const String alreadyHaveAccount = 'Already have an account?';
  static const String welcomeBack = 'Welcome back';
  static const String loginSubtitle = 'Login to continue to ParkShare';
  static const String createAccountTitle = 'Create your account';
  static const String createAccountSubtitle =
      'All details on a single page. It takes less than a minute.';
  static const String upiId = 'UPI ID';
  static const String upiIdHint = 'yourname@bank';
  static const String upiIdOwnerHint =
      'Optional. Used only for legacy UPI payments if enabled.';
  static const String upiIdUserHint =
      'Optional. You can add it later in your profile.';
  static const String showPassword = 'Show password';
  static const String resetPasswordTitle = 'Reset Password';
  static const String resetPasswordSubtitle =
      'Choose a new password for your account';
  static const String forgotPasswordTitle = 'Forgot Password';
  static const String forgotPasswordSubtitle =
      'Enter your email and we will send you a verification code';
  static const String otpTitle = 'Verify OTP';
  static const String otpSubtitle =
      'Enter the 6-digit code we sent to your email';
  static const String resendOtp = 'Resend OTP';
  static const String sendOtp = 'Send OTP';
  static const String verify = 'Verify';
  static const String submit = 'Submit';

  // Errors / states
  static const String errorGeneric = 'Something went wrong. Please try again.';
  static const String noNetwork =
      'Unable to reach the server. Check your internet connection.';
  static const String retry = 'Retry';
  static const String unableToLoad = 'Unable to load';

  // Payment (UPI + Cash on Delivery)
  static const String paySecurely = 'Pay securely';
  static const String choosePaymentMethod = 'Choose a payment method';
  static const String payNow = 'Pay Now';
  static const String bookOnCash = 'Book on Cash';
  static const String ownerUpiMissing =
      'This parking owner has not configured a UPI ID yet. Please choose Cash '
      'on Delivery or contact the owner.';
  static const String checkingUpi = 'Checking for a UPI app on this device…';
  static const String noUpiApp =
      'No UPI payment app is available on this device. Install Google Pay, '
      'PhonePe, Paytm or any BHIM UPI app and try again, or pay Cash on '
      'Delivery.';
  static const String upiCancelled =
      'Payment was cancelled. You can try again or pay Cash on Delivery.';
  static const String paymentSuccessful = 'Payment Successful';
  static const String bookingConfirmedNote =
      'Your booking is confirmed. The owner can see it now.';
  static const String transactionId = 'Transaction ID';
  static const String paidTo = 'Paid to';
  static const String done = 'Done';
  static const String codTitle = 'Cash on Delivery';
  static const String codSubtitle = 'Please contact your parking owner';
  static const String codInstruction =
      'Pay the amount in cash and hand it over to the owner. Your slot is '
      'confirmed once the owner marks the cash as received.';
  static const String codCallOwner = 'Call owner';
  static const String codMarkReceived = 'Mark COD Received';
  static const String codConfirmTitle = 'Confirm cash received?';
  static const String codConfirmBody =
      'This marks the cash payment as received, confirms the booking and '
      'adds the amount to your earnings. This cannot be undone.';
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
}
