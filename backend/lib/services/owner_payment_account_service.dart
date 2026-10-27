import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/parking_service.dart';
import 'package:parkshare_backend/services/payout_details_cipher.dart';
import 'package:postgres/postgres.dart';

/// Provider keys stored on `owner_payment_accounts.provider`.
///
/// Only Razorpay is wired today; the column exists so a second provider can be
/// added without a competing settlement path.
class OwnerPaymentProvider {
  OwnerPaymentProvider._();
  static const String razorpay = 'RAZORPAY';
}

/// Onboarding states stored on `owner_payment_accounts.razorpay_onboarding_status`.
///
/// IMPORTANT: ParkShare must never *claim* a provider state it has not received.
/// With Razorpay Route onboarding not yet integrated, a locally saved setup is
/// [pending] — never [verified]. Only a provider callback may move it to
/// [verified] / [actionRequired] / [rejected].
class OnboardingStatus {
  OnboardingStatus._();
  static const String notStarted = 'NOT_STARTED';
  static const String pending = 'PENDING';
  static const String verified = 'VERIFIED';
  static const String actionRequired = 'ACTION_REQUIRED';
  static const String rejected = 'REJECTED';

  static const Set<String> all = {
    notStarted,
    pending,
    verified,
    actionRequired,
    rejected,
  };

  /// States a provider (not the client) is allowed to set. Used to stop a
  /// re-submitted setup form downgrading a decision the provider already made.
  static const Set<String> providerOwned = {verified, actionRequired, rejected};
}

/// Legal / business account types accepted by the setup form.
class OwnerAccountType {
  OwnerAccountType._();
  static const String individual = 'INDIVIDUAL';
  static const String proprietor = 'PROPRIETOR';
  static const String company = 'COMPANY';
  static const Set<String> all = {individual, proprietor, company};

  static String label(String type) => switch (type) {
    individual => 'Individual',
    proprietor => 'Proprietor',
    company => 'Company / Business',
    _ => type,
  };
}

/// Owner payment & settlement account.
///
/// This is the ONLY code that reads or writes `owner_payment_accounts`. It is a
/// hard privacy boundary:
///   * the owner-facing projection exposes only `bank_last4`, never the full
///     account number, IFSC, ciphertext or provider secret;
///   * the full destination needed to make a manual bank payout is stored
///     AES-256-GCM encrypted (see [PayoutDetailsCipher]) and is readable only
///     through the admin-only settlement service;
///   * the owner id always comes from the verified JWT, never from a client
///     field, so one owner can never read or edit another's setup.
class OwnerPaymentAccountService {
  /// IFSC: 4 letters, a literal 0, then 6 alphanumerics (RBI format).
  static final RegExp _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Indian bank account numbers are 9-18 digits.
  static final RegExp _accountNumber = RegExp(r'^\d{9,18}$');

  /// Indian mobile: 10 digits starting 6-9.
  static final RegExp _mobile = RegExp(r'^[6-9]\d{9}$');

  // ---------------------------------------------------------------------
  // GET /api/payments/owner/payment-account
  // ---------------------------------------------------------------------

  /// Masked status/summary for the authenticated owner. Returns a
  /// `NOT_STARTED` shape when no setup exists yet, so the app has a stable
  /// contract to render in both states.
  Future<Map<String, dynamic>> getForOwner({required String ownerId}) async {
    if (!ParkingService.isUuid(ownerId)) {
      throw ApiError.validation('A valid owner id is required.');
    }
    final row = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        SELECT provider, razorpay_onboarding_status, razorpay_settlement_enabled,
               legal_name, account_type, account_holder_name, bank_last4,
               consent_accepted_at, updated_at,
               (payout_account_number_encrypted IS NOT NULL
                 AND payout_ifsc_encrypted IS NOT NULL) AS payout_details_available
        FROM owner_payment_accounts
        WHERE owner_id = @ownerId
        '''),
        parameters: {'ownerId': ownerId},
      );
      return res.isEmpty ? null : res.first.toColumnMap();
    });
    return maskProjection(row, ownerId: ownerId);
  }

  // ---------------------------------------------------------------------
  // PUT /api/payments/owner/payment-account
  // ---------------------------------------------------------------------

  /// Validates and upserts the authenticated owner's setup.
  ///
  /// The full bank account number and IFSC are validated and stored encrypted
  /// (never in plaintext). `settlement_enabled` is left FALSE and the onboarding
  /// status becomes [OnboardingStatus.pending]: ParkShare does not fake a
  /// completed Razorpay Route onboarding. The encrypted destination is used by
  /// the admin-only manual settlement path instead.
  Future<Map<String, dynamic>> saveForOwner({
    required String ownerId,
    required Map<String, dynamic> body,
  }) async {
    if (!ParkingService.isUuid(ownerId)) {
      throw ApiError.validation('A valid owner id is required.');
    }

    final legalName = _str(body['legalName']);
    final accountType = _str(body['accountType']).toUpperCase();
    final mobile = _str(body['mobile']).replaceAll(RegExp(r'\s|-'), '');
    final email = _str(body['email']).toLowerCase();
    final holder = _str(body['accountHolderName']);
    final accountNumber = _str(body['bankAccountNumber'])
        .replaceAll(RegExp(r'\s|-'), '');
    final confirm = _str(body['confirmBankAccountNumber'])
        .replaceAll(RegExp(r'\s|-'), '');
    final ifsc = _str(body['ifscCode']).toUpperCase().replaceAll(' ', '');
    final consent = body['consent'] == true;

    if (legalName.length < 2) {
      throw ApiError.validation('Legal / account holder name is required.');
    }
    if (!OwnerAccountType.all.contains(accountType)) {
      throw ApiError.validation('Select a valid account type.');
    }
    if (!_mobile.hasMatch(mobile)) {
      throw ApiError.validation('Enter a valid 10-digit mobile number.');
    }
    if (!_email.hasMatch(email)) {
      throw ApiError.validation('Enter a valid email address.');
    }
    if (holder.length < 2) {
      throw ApiError.validation('Bank account holder name is required.');
    }
    if (!_accountNumber.hasMatch(accountNumber)) {
      throw ApiError.validation(
        'Enter a valid bank account number (9-18 digits).',
      );
    }
    if (accountNumber != confirm) {
      throw ApiError.validation('Bank account numbers do not match.');
    }
    if (!_ifsc.hasMatch(ifsc)) {
      throw ApiError.validation('Enter a valid IFSC code (e.g. HDFC0001234).');
    }
    if (!consent) {
      throw ApiError.validation(
        'Please accept the settlement terms to continue.',
      );
    }

    final last4 = accountNumber.substring(accountNumber.length - 4);
    final encryptedAccount = PayoutDetailsCipher.encrypt(accountNumber);
    final encryptedIfsc = PayoutDetailsCipher.encrypt(ifsc);

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        INSERT INTO owner_payment_accounts (
          owner_id, provider, razorpay_onboarding_status,
          razorpay_settlement_enabled,
          legal_name, account_type, account_holder_name, bank_last4,
          payout_account_number_encrypted, payout_ifsc_encrypted,
          payout_details_updated_at,
          contact_mobile, contact_email, consent_accepted_at, updated_at
        ) VALUES (
          @ownerId, @provider, @status,
          FALSE,
          @legalName, @accountType, @holder, @last4,
          @encryptedAccount, @encryptedIfsc, NOW(),
          @mobile, @email, NOW(), NOW()
        )
        ON CONFLICT (owner_id) DO UPDATE SET
          provider = @provider,
          -- Never downgrade a state the provider already decided.
          razorpay_onboarding_status = CASE
            WHEN owner_payment_accounts.razorpay_onboarding_status
                 IN ('VERIFIED', 'ACTION_REQUIRED', 'REJECTED')
            THEN owner_payment_accounts.razorpay_onboarding_status
            ELSE @status
          END,
          legal_name = @legalName,
          account_type = @accountType,
          account_holder_name = @holder,
          bank_last4 = @last4,
          payout_account_number_encrypted = @encryptedAccount,
          payout_ifsc_encrypted = @encryptedIfsc,
          payout_details_updated_at = NOW(),
          contact_mobile = @mobile,
          contact_email = @email,
          consent_accepted_at =
            COALESCE(owner_payment_accounts.consent_accepted_at, NOW()),
          updated_at = NOW()
        '''),
        parameters: {
          'ownerId': ownerId,
          'provider': OwnerPaymentProvider.razorpay,
          'status': OnboardingStatus.pending,
          'legalName': legalName,
          'accountType': accountType,
          'holder': holder,
          'last4': last4,
          'encryptedAccount': encryptedAccount,
          'encryptedIfsc': encryptedIfsc,
          'mobile': mobile,
          'email': email,
        },
      );
    });

    return getForOwner(ownerId: ownerId);
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Builds the owner-facing projection. Never includes the full account
  /// number, IFSC, provider secret or linked-account id.
  ///
  /// Public (not `_`-private) so the response contract — a strict whitelist of
  /// safe keys — can be regression-tested directly.
  static Map<String, dynamic> maskProjection(
    Map<String, dynamic>? row, {
    required String ownerId,
  }) {
    if (row == null) {
      return {
        'ownerId': ownerId,
        'provider': OwnerPaymentProvider.razorpay,
        'onboardingStatus': OnboardingStatus.notStarted,
        'settlementEnabled': false,
        'setupCompleted': false,
        'accountHolderName': '',
        'legalName': '',
        'accountType': '',
        'bankLast4': '',
        'payoutDetailsAvailable': false,
        'consentAcceptedAt': null,
        'updatedAt': null,
      };
    }

    final rawStatus = (row['razorpay_onboarding_status']?.toString() ?? '')
        .trim()
        .toUpperCase();
    final status = rawStatus.isEmpty ? OnboardingStatus.notStarted : rawStatus;

    return {
      'ownerId': ownerId,
      'provider': (row['provider']?.toString() ?? '').trim().isEmpty
          ? OwnerPaymentProvider.razorpay
          : row['provider'].toString(),
      'onboardingStatus': status,
      'settlementEnabled': row['razorpay_settlement_enabled'] == true,
      'setupCompleted': true,
      'accountHolderName': row['account_holder_name']?.toString() ?? '',
      'legalName': row['legal_name']?.toString() ?? '',
      'accountType': row['account_type']?.toString() ?? '',
      'bankLast4': row['bank_last4']?.toString() ?? '',
      'payoutDetailsAvailable': row['payout_details_available'] == true,
      'consentAcceptedAt': row['consent_accepted_at']?.toString(),
      'updatedAt': row['updated_at']?.toString(),
    };
  }

  static String _str(Object? value) => value?.toString().trim() ?? '';
}
