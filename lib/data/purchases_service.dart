import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

/// PlatePatch Pro, as the rest of the app sees it.
///
/// Every field has a safe value when RevenueCat is unreachable, unconfigured,
/// or the device is offline. Nothing in the free experience is allowed to
/// depend on this succeeding.
@immutable
class ProStatus {
  const ProStatus({
    this.isPro = false,
    this.configured = false,
    this.offering,
    this.loading = false,
    this.purchasing = false,
    this.message,
  });

  final bool isPro;

  /// Whether the SDK was given an API key at build time and configured cleanly.
  final bool configured;
  final Offering? offering;
  final bool loading;
  final bool purchasing;

  /// A user-facing note about the last purchase or restore attempt.
  final String? message;

  Package? get monthly => offering?.monthly;
  Package? get annual => offering?.annual;

  bool get hasProducts => monthly != null || annual != null;

  ProStatus copyWith({
    bool? isPro,
    bool? configured,
    Offering? offering,
    bool? loading,
    bool? purchasing,
    String? message,
    bool clearMessage = false,
  }) =>
      ProStatus(
        isPro: isPro ?? this.isPro,
        configured: configured ?? this.configured,
        offering: offering ?? this.offering,
        loading: loading ?? this.loading,
        purchasing: purchasing ?? this.purchasing,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// The store this build sells through, by name. Apple rejects apps that
/// mention another store's name in their copy, and the reverse reads as a bug
/// on Android, so no user-facing string hardcodes either one.
String get storeName =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'the App Store' : 'Google Play';

/// Where the user manages or cancels a subscription on this platform.
String get manageSubscriptionsUrl => defaultTargetPlatform == TargetPlatform.iOS
    ? 'https://apps.apple.com/account/subscriptions'
    : 'https://play.google.com/store/account/subscriptions';

/// Renders a store's introductory offer as words. The store reports a unit and
/// a count — a 7-day trial and a 1-week trial are the same thing described
/// differently — so both have to be handled or the paywall lies about the
/// trial length.
String? describeIntroOffer(int? units, PeriodUnit? unit) {
  if (units == null || units <= 0 || unit == null || unit == PeriodUnit.unknown) {
    return null;
  }
  final noun = switch (unit) {
    PeriodUnit.day => 'day',
    PeriodUnit.week => 'week',
    PeriodUnit.month => 'month',
    PeriodUnit.year => 'year',
    PeriodUnit.unknown => '',
  };
  return '$units ${units == 1 ? noun : '${noun}s'} free';
}

/// Thin wrapper over the RevenueCat SDK. Kept behind an interface so widget
/// tests can run the whole app without touching the billing plugin.
abstract class PurchasesService {
  Future<ProStatus> init();

  Future<ProStatus> purchase(Package package);

  Future<ProStatus> restore();

  /// RevenueCat's id for this install. The scan API sends it so the server can
  /// ask RevenueCat directly whether the subscription is real, rather than
  /// believing the app.
  Future<String?> appUserId();
}

class RevenueCatService implements PurchasesService {
  RevenueCatService({required this.apiKey, this.entitlementId = 'platepatch_pro'});

  /// Supplied at build time:
  /// `flutter build appbundle --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx`
  final String apiKey;
  final String entitlementId;

  static const _offeringId = 'default';

  ProStatus _status = const ProStatus();

  /// `configure` is a once-per-process call. A retry after an offline start
  /// must refresh offerings without configuring the SDK a second time.
  bool _sdkConfigured = false;

  @override
  Future<ProStatus> init() async {
    if (apiKey.isEmpty) {
      // Ship-safe default: the app is fully usable, Pro simply cannot be sold.
      _status = const ProStatus(configured: false);
      return _status;
    }
    _status = _status.copyWith(loading: true);
    try {
      if (!_sdkConfigured) {
        await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.error);
        await Purchases.configure(PurchasesConfiguration(apiKey));
        _sdkConfigured = true;
      }
      final info = await Purchases.getCustomerInfo();
      final offerings = await Purchases.getOfferings();
      _status = ProStatus(
        isPro: _isEntitled(info),
        configured: true,
        offering: offerings.getOffering(_offeringId) ?? offerings.current,
      );
    } catch (e) {
      // Offline, misconfigured dashboard, Play services missing — none of
      // these should stop someone from patching their lunch.
      _status = ProStatus(configured: false, message: _readable(e));
    }
    return _status;
  }

  @override
  Future<ProStatus> purchase(Package package) async {
    _status = _status.copyWith(purchasing: true, clearMessage: true);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _status = _status.copyWith(
        isPro: _isEntitled(result.customerInfo),
        purchasing: false,
        message: _isEntitled(result.customerInfo) ? 'You are on PlatePatch Pro.' : null,
      );
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      _status = _status.copyWith(
        purchasing: false,
        // A deliberate cancel is not an error worth shouting about.
        message: code == PurchasesErrorCode.purchaseCancelledError ? null : _readable(e),
        clearMessage: code == PurchasesErrorCode.purchaseCancelledError,
      );
    } catch (e) {
      _status = _status.copyWith(purchasing: false, message: _readable(e));
    }
    return _status;
  }

  @override
  Future<ProStatus> restore() async {
    _status = _status.copyWith(purchasing: true, clearMessage: true);
    try {
      final info = await Purchases.restorePurchases();
      final entitled = _isEntitled(info);
      _status = _status.copyWith(
        isPro: entitled,
        purchasing: false,
        message: entitled ? 'Pro restored.' : 'No previous purchase found on this account.',
      );
    } catch (e) {
      _status = _status.copyWith(purchasing: false, message: _readable(e));
    }
    return _status;
  }

  @override
  Future<String?> appUserId() async {
    if (!_sdkConfigured) return null;
    try {
      return await Purchases.appUserID;
    } catch (_) {
      return null;
    }
  }

  bool _isEntitled(CustomerInfo info) => info.entitlements.active.containsKey(entitlementId);

  String _readable(Object e) {
    if (e is PlatformException) {
      final message = e.message;
      if (message != null && message.isNotEmpty) return message;
    }
    return 'Something went wrong talking to the store. Please try again.';
  }
}

/// Used in tests and in any build without an API key.
class InertPurchasesService implements PurchasesService {
  InertPurchasesService({this.isPro = false, this.userId});

  final bool isPro;

  /// Lets a test pretend a subscription exists without a store.
  final String? userId;

  @override
  Future<ProStatus> init() async => ProStatus(isPro: isPro, configured: false);

  @override
  Future<ProStatus> purchase(Package package) async =>
      ProStatus(isPro: isPro, configured: false, message: 'Purchases are not available yet.');

  @override
  Future<ProStatus> restore() async =>
      ProStatus(isPro: isPro, configured: false, message: 'Purchases are not available yet.');

  @override
  Future<String?> appUserId() async => userId;
}
