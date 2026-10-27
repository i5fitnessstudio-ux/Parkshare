import 'package:flutter/foundation.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/services/payment_service.dart';
import '../../../shared/models/owner_payment_info.dart';

/// Owner "Payments & Settlements" state.
///
/// Loads the masked owner payment account and the server-computed earnings /
/// settlement totals, and saves the payout setup. The owner id is never held
/// or sent here: the backend derives it from the JWT, so this provider cannot
/// accidentally address another owner.
class OwnerPaymentsProvider extends ChangeNotifier {
  final PaymentService _payments;

  OwnerPaymentAccount? _account;
  OwnerEarningsSummary? _earnings;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  int _sessionEpoch = 0;

  bool _isCurrent(int epoch) => epoch == _sessionEpoch;

  OwnerPaymentsProvider({PaymentService? paymentService})
    : _payments = paymentService ?? PaymentService();

  OwnerPaymentAccount? get account => _account;
  OwnerEarningsSummary? get earnings => _earnings;
  bool get loading => _loading;

  /// True while a setup save is in flight — used to block double submits.
  bool get saving => _saving;
  String? get error => _error;

  /// True when the owner has not completed any payout setup yet.
  bool get needsSetup => _account?.isNotStarted ?? true;

  /// True once a setup exists (even if the provider has not verified it).
  bool get hasSetup => _account?.setupCompleted ?? false;

  /// True when settlements can actually be paid out.
  bool get settlementEnabled => _account?.settlementEnabled ?? false;

  /// Owner share awaiting settlement, in integer paise.
  int get pendingSettlementPaise => _earnings?.pendingSettlementPaise ?? 0;

  /// Owner share already settled, in integer paise.
  int get settledPaise => _earnings?.settledPaise ?? 0;

  /// Loads the account + earnings concurrently. Failures are non-fatal: a
  /// missing account is treated as NOT_STARTED and a missing earnings call
  /// simply leaves the totals empty (the setup flow still works).
  Future<void> load({required String token}) async {
    final epoch = _sessionEpoch;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _payments.fetchOwnerPaymentAccount(token: token),
        _payments.fetchOwnerEarnings(token: token),
      ]);
      if (!_isCurrent(epoch)) return;
      _account = results[0] as OwnerPaymentAccount;
      _earnings = results[1] as OwnerEarningsSummary;
    } catch (e) {
      ErrorMessages.logTechnical('OwnerPaymentsProvider.load', e);
      if (_isCurrent(epoch)) _error = ErrorMessages.forUi(e);
    } finally {
      if (_isCurrent(epoch)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Saves the setup. Returns null on success, or a user-safe error message.
  ///
  /// Guards against a double submit: a second call while [saving] is true is a
  /// no-op that returns the current (in-flight) state message.
  ///
  /// The endpoint is the authenticated Owner payment-account API. The backend
  /// stores the full bank destination encrypted and returns only a masked
  /// projection. The setup intentionally stays PENDING: Razorpay Route is not
  /// activated, so the app must never claim that automatic settlement is on.
  Future<String?> save({
    required String token,
    required OwnerPaymentAccountInput input,
  }) async {
    if (_saving) return null;
    final epoch = _sessionEpoch;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final account = await _payments.saveOwnerPaymentAccount(
        token: token,
        input: input,
      );
      if (!_isCurrent(epoch)) return null;
      _account = account;
      return null;
    } catch (e) {
      ErrorMessages.logTechnical('OwnerPaymentsProvider.save', e);
      if (!_isCurrent(epoch)) return null;
      final message = ErrorMessages.forUi(e);
      _error = message;
      return message;
    } finally {
      if (_isCurrent(epoch)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  void resetForAccountSwitch() {
    _sessionEpoch++;
    _account = null;
    _earnings = null;
    _error = null;
    _loading = false;
    _saving = false;
    notifyListeners();
  }
}
