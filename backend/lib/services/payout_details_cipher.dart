import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:pointycastle/export.dart';

/// Raised when stored payout details cannot be decrypted.
///
/// The message is deliberately generic: it must never include key material,
/// ciphertext or any part of the bank account.
class PayoutDetailsCipherException implements Exception {
  const PayoutDetailsCipherException();

  @override
  String toString() => 'PayoutDetailsCipherException';
}

/// Reversible encryption for the owner bank details needed by a manual payout.
///
/// WHY THIS EXISTS
/// ---------------
/// Razorpay Route is unavailable for this business (the September 2025 RBI
/// Payment Aggregator rules require >= INR 40 lakh domestic turnover and an
/// approved payer-payee declaration). Razorpay's own documented fallback is a
/// two-step flow: collect the customer payment normally, then pay the owner
/// out-of-band.
///
/// A manual bank payout needs the full account number and IFSC, which the
/// original implementation validated and then discarded. Discarding them made
/// "manual settlement" a ledger checkbox that could not actually pay anyone.
/// They are now stored encrypted with AES-256-GCM, with a fresh 96-bit nonce
/// per value. A tampered ciphertext fails authentication instead of yielding a
/// wrong account number.
///
/// FORMAT
/// ------
/// `v1.<base64url(nonce || ciphertext || tag)>`
///
/// The key is derived from `OWNER_PAYOUT_ENCRYPTION_KEY` with SHA-256, so any
/// sufficiently long secret can be used. Production startup requires the
/// variable and a minimum length; development uses a published placeholder.
class PayoutDetailsCipher {
  PayoutDetailsCipher._();

  static const String _prefix = 'v1.';
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static final Uint8List _aad = Uint8List.fromList(
    utf8.encode('parkshare-owner-payout-v1'),
  );

  static Uint8List get _key {
    final secret = Config.ownerPayoutEncryptionKey.trim();
    if (secret.isEmpty) {
      throw const PayoutDetailsCipherException();
    }
    return Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes);
  }

  /// Encrypts one non-empty payout value. Returns `v1.<base64url>`.
  static String encrypt(String plaintext) {
    final value = plaintext.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'plaintext', 'must not be empty');
    }
    final nonce = _randomNonce();
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_key), 128, nonce, _aad));
    final sealed = cipher.process(Uint8List.fromList(utf8.encode(value)));
    final combined = Uint8List(nonce.length + sealed.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + sealed.length, sealed);
    return '$_prefix${base64Url.encode(combined)}';
  }

  /// Decrypts a value produced by [encrypt].
  ///
  /// Throws [PayoutDetailsCipherException] for an unknown format, a wrong key,
  /// or modified ciphertext. No partial plaintext is ever returned.
  static String decrypt(String encoded) {
    final raw = encoded.trim();
    if (!raw.startsWith(_prefix)) {
      throw const PayoutDetailsCipherException();
    }
    final Uint8List combined;
    try {
      combined = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(raw.substring(_prefix.length))),
      );
    } catch (_) {
      throw const PayoutDetailsCipherException();
    }
    if (combined.length <= _nonceLength + _tagLength) {
      throw const PayoutDetailsCipherException();
    }

    final nonce = combined.sublist(0, _nonceLength);
    final sealed = combined.sublist(_nonceLength);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(_key), 128, nonce, _aad));
      final clear = cipher.process(sealed);
      return utf8.decode(clear);
    } catch (_) {
      throw const PayoutDetailsCipherException();
    }
  }

  static Uint8List _randomNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_nonceLength, (_) => random.nextInt(256)),
    );
  }
}
