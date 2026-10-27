import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_strings.dart';
import '../core/network/api_client.dart';
import '../core/services/payment_service.dart';
import '../core/storage/session_storage.dart';
import '../core/storage/token_storage.dart';
import '../modules/account/screens/delete_account_screen.dart';
import '../modules/auth/providers/auth_provider.dart';
import '../modules/auth/screens/forgot_password_screen.dart';
import '../modules/auth/screens/login_screen.dart';
import '../modules/auth/screens/otp_verification_screen.dart';
import '../modules/auth/screens/register_screen.dart';
import '../modules/auth/screens/reset_password_screen.dart';
import '../modules/auth/screens/role_selection_new_screen.dart';
import '../modules/auth/services/auth_service.dart';
import '../modules/booking/providers/booking_provider.dart';
import '../modules/booking/providers/payment_provider.dart';
import '../modules/inbox/chat_screen.dart';
import '../modules/inbox/providers/inbox_provider.dart';
import '../modules/legal/legal_document_screen.dart';
import '../modules/onboarding/blue_splash_screen.dart';
import '../modules/onboarding/onboarding_intro_screen.dart';
import '../modules/owner/add_parking/add_parking_screen.dart';
import '../modules/owner/home/owner_dashboard_screen.dart';
import '../modules/owner/payments/owner_payment_setup_screen.dart';
import '../modules/owner/payments/payments_settlements_screen.dart';
import '../modules/owner/providers/owner_dashboard_provider.dart';
import '../modules/owner/providers/owner_parking_provider.dart';
import '../modules/owner/providers/owner_payments_provider.dart';
import '../modules/shared/providers/location_provider.dart';
import '../modules/splash/splash_screen.dart';
import '../modules/user/booking/booking_screen.dart';
import '../modules/user/booking/cod_pending_screen.dart';
import '../modules/user/booking/payment_screen.dart';
import '../modules/user/booking/payment_success_screen.dart';
import '../modules/user/home/user_home_screen.dart';
import '../modules/user/parking/parking_detail_screen.dart';
import '../modules/user/providers/user_home_tab_provider.dart';
import '../modules/user/providers/user_map_provider.dart';
import '../modules/vehicle/providers/vehicle_provider.dart';
import '../modules/vehicle/vehicle_form_screen.dart';
import '../shared/models/booking.dart';
import '../shared/models/owner_payment_info.dart';
import '../shared/models/parking.dart';
import '../shared/models/vehicle.dart';
import 'routes.dart';
import 'theme.dart';

/// Root widget: wires providers and themes, defines routing.
class ParkShareApp extends StatefulWidget {
  const ParkShareApp({super.key});

  @override
  State<ParkShareApp> createState() => _ParkShareAppState();
}

class _ParkShareAppState extends State<ParkShareApp> {
  late final AuthProvider _authProvider;
  late final OwnerParkingProvider _ownerParkingProvider;
  late final OwnerDashboardProvider _ownerDashboardProvider;
  late final OwnerPaymentsProvider _ownerPaymentsProvider;
  late final LocationProvider _locationProvider;
  late final UserMapProvider _userMapProvider;
  late final UserHomeTabProvider _userHomeTabProvider;
  late final VehicleProvider _vehicleProvider;
  late final BookingProvider _bookingProvider;
  late final PaymentProvider _paymentProvider;
  late final InboxProvider _inboxProvider;

  /// Identity of the currently loaded session. Empty means signed out.
  ///
  /// A reset is triggered ONLY when this value changes. The previous code reset
  /// payment state from `build`, which runs for theme changes, keyboard insets
  /// and every auth notification: it could dispose an active Razorpay Checkout
  /// while a payment was in flight.
  String _sessionIdentity = '';

  @override
  void initState() {
    super.initState();
    final apiClient = ApiClient();
    _authProvider = AuthProvider(
      authService: AuthService(apiClient),
      tokenStorage: TokenStorage(),
      sessionStorage: SessionStorage(),
    );
    _ownerParkingProvider = OwnerParkingProvider(client: apiClient);
    _ownerDashboardProvider = OwnerDashboardProvider();
    _ownerPaymentsProvider = OwnerPaymentsProvider();
    _locationProvider = LocationProvider();
    _userMapProvider = UserMapProvider();
    _userHomeTabProvider = UserHomeTabProvider();
    _vehicleProvider = VehicleProvider();
    _bookingProvider = BookingProvider();
    _paymentProvider = PaymentProvider();
    _inboxProvider = InboxProvider();
    _sessionIdentity = _identityOfCurrentUser();
    _authProvider.addListener(_onAuthChanged);
  }

  String _identityOfCurrentUser() {
    final user = _authProvider.user;
    if (user == null) return '';
    return '${user.id}|${user.role}';
  }

  void _onAuthChanged() {
    final next = _identityOfCurrentUser();
    if (next == _sessionIdentity) return;
    _sessionIdentity = next;
    // The auth notification can originate while descendants are building.
    // Clear on the next frame so provider notifications cannot race a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resetAccountScopedState();
    });
  }

  void _resetAccountScopedState() {
    try {
      _paymentProvider.resetForAccountSwitch();
    } catch (_) {}
    try {
      _ownerPaymentsProvider.resetForAccountSwitch();
    } catch (_) {}
    try {
      _bookingProvider.resetForAccountSwitch();
    } catch (_) {}
    try {
      _ownerDashboardProvider.resetForAccountSwitch();
    } catch (_) {}
    try {
      _ownerParkingProvider.resetForAccountSwitch();
    } catch (_) {}
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _authProvider.dispose();
    _ownerParkingProvider.dispose();
    _ownerDashboardProvider.dispose();
    _ownerPaymentsProvider.dispose();
    _locationProvider.dispose();
    _userMapProvider.dispose();
    _userHomeTabProvider.dispose();
    _vehicleProvider.dispose();
    _bookingProvider.dispose();
    _paymentProvider.dispose();
    _inboxProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _ownerParkingProvider),
        ChangeNotifierProvider.value(value: _ownerDashboardProvider),
        ChangeNotifierProvider.value(value: _ownerPaymentsProvider),
        ChangeNotifierProvider.value(value: _locationProvider),
        ChangeNotifierProvider.value(value: _userMapProvider),
        ChangeNotifierProvider.value(value: _userHomeTabProvider),
        ChangeNotifierProvider.value(value: _vehicleProvider),
        ChangeNotifierProvider.value(value: _bookingProvider),
        ChangeNotifierProvider.value(value: _paymentProvider),
        ChangeNotifierProvider.value(value: _inboxProvider),
      ],
      child: ListenableBuilder(
        listenable: _authProvider,
        builder: (context, _) {
          final theme = AppTheme.forRole(_authProvider.user?.role);
          return MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: const BlueSplashScreen(),
            onGenerateRoute: _generateRoute,
          );
        },
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final args = settings.arguments;
    switch (settings.name) {
      case AppRoutes.splash:
        return _page(const SplashScreen(), settings);
      case AppRoutes.blueSplash:
        return _page(const BlueSplashScreen(), settings);
      case AppRoutes.onboarding:
        return _page(const OnboardingIntroScreen(), settings);
      case AppRoutes.onboardingIntro:
        return _page(const OnboardingIntroScreen(), settings);
      case AppRoutes.roleSelection:
        return _page(const RoleSelectionNewScreen(), settings);
      case AppRoutes.login:
        return _page(LoginScreen(arguments: args), settings);
      case AppRoutes.register:
        return _page(RegisterScreen(role: args as String?), settings);
      case AppRoutes.forgotPassword:
        return _page(
          ForgotPasswordScreen(args as Map<String, dynamic>?),
          settings,
        );
      // ---- Legal documents (linked from the Create Account consent row) ----
      case AppRoutes.termsConditions:
        return _page(const LegalDocumentScreen.terms(), settings);
      case AppRoutes.privacyPolicy:
        return _page(const LegalDocumentScreen.privacy(), settings);
      case AppRoutes.otpVerification:
        return _page(
          OtpVerificationScreen(args as Map<String, dynamic>?),
          settings,
        );
      case AppRoutes.resetPassword:
        return _page(
          ResetPasswordScreen(args as Map<String, dynamic>?),
          settings,
        );
      case AppRoutes.ownerDashboard:
        return _page(const OwnerDashboardScreen(), settings);
      case AppRoutes.ownerPayments:
        return _page(const PaymentsSettlementsScreen(), settings);
      case AppRoutes.ownerPaymentSetup:
        return _page(const OwnerPaymentSetupScreen(), settings);
      case AppRoutes.userHome:
        return _page(const UserHomeScreen(), settings);
      case AppRoutes.deleteAccount:
        return _page(const DeleteAccountScreen(), settings);

      // ---- Phase 2-5 ----
      case AppRoutes.addParking:
        // The SAME wizard is used to create and to edit. Passing a listing
        // prefills the draft and switches the final button to "Update".
        final map = (args as Map?) ?? const {};
        return _page(
          AddParkingScreen(
            existing: map['parking'] is ParkingListing
                ? map['parking'] as ParkingListing
                : null,
          ),
          settings,
        );
      case AppRoutes.parkingDetail:
        final map = (args as Map?) ?? const {};
        return _page(
          ParkingDetailScreen(
            parkingId: map['parkingId']?.toString() ?? '',
            parking: map['parking'] is ParkingListing
                ? map['parking'] as ParkingListing
                : null,
          ),
          settings,
        );
      case AppRoutes.booking:
        final map = (args as Map?) ?? const {};
        return _page(
          BookingScreen(parking: map['parking'] as ParkingListing),
          settings,
        );
      case AppRoutes.payment:
        final map = (args as Map?) ?? const {};
        return _page(
          PaymentScreen(
            booking: map['booking'] as Booking,
            parking: map['parking'] is ParkingListing
                ? map['parking'] as ParkingListing
                : null,
          ),
          settings,
        );
      case AppRoutes.paymentSuccess:
        return _page(PaymentSuccessScreen(booking: args as Booking), settings);
      case AppRoutes.codPending:
        final map = (args as Map?) ?? const {};
        final codBooking = map['booking'] is Booking
            ? map['booking'] as Booking
            : null;
        // The COD route is always pushed with a booking; if it somehow is not,
        // fall back home instead of crashing.
        if (codBooking == null) return _page(const UserHomeScreen(), settings);
        return _page(
          CodPendingScreen(
            booking: codBooking,
            // The COD endpoint returns the booking plus an `ownerContact`
            // block; fall back to the booking's own owner data when absent.
            owner: map['ownerContact'] is OwnerContact
                ? map['ownerContact'] as OwnerContact
                : PaymentService.ownerContactFromBooking(codBooking),
          ),
          settings,
        );
      case AppRoutes.chat:
        final map = (args as Map?) ?? const {};
        return _page(
          ChatScreen(args: Map<String, dynamic>.from(map)),
          settings,
        );
      case AppRoutes.vehicleForm:
        final map = (args as Map?) ?? const {};
        return _page(
          VehicleFormScreen(
            vehicle: map['vehicle'] is Vehicle
                ? map['vehicle'] as Vehicle
                : null,
          ),
          settings,
        );
      default:
        return null;
    }
  }

  MaterialPageRoute<dynamic> _page(Widget screen, RouteSettings settings) {
    return MaterialPageRoute(settings: settings, builder: (_) => screen);
  }
}
