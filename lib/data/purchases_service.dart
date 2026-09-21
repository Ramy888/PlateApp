import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

/// Plate Pro, as the rest of the app sees it.
///
/// Every field has a safe value when RevenueCat is unreachable, unconfigured,
/// or the device is offline. Nothing in the free experience is allowed to
/// depend on this succeeding.
/// Which subscription someone is actually on.
///
/// Needed because "Pro" is not one thing to the person paying for it: someone
/// on the monthly plan can still be sold the yearly one, and someone already on
/// yearly must never be offered an upgrade they already have.
enum ProPlan { none, monthly, yearly }

@immutable
class ProStatus {
  const ProStatus({
    this.isPro = false,
    this.configured = false,
    this.offering,
    this.loading = false,
    this.purchasing = false,
    this.message,
    this.plan = ProPlan.none,
    this.inTrial = false,
  });

  final bool isPro;

  /// The plan behind [isPro], when the store says which.
  final ProPlan plan;

  /// Whether the current period is the introductory free one. Worth saying out
  /// loud: someone in a trial has not been charged yet and should be told so
  /// rather than discovering it.
  final bool inTrial;

  /// Only a monthly subscriber can move up, and only if the store offered an
  /// annual package to move to.
  bool get canUpgradeToYearly => isPro && plan == ProPlan.monthly && annual != null;

  /// Whether the SDK was given an API key at build time and configured cleanly.
  final bool configured;
  final Offering? offering;
  final bool loading;
  final bool purchasing;

  /// A user-facing note about the last purchase or restore attempt.
  final String? message;

  Package? get monthly => pickPackage(offering, PackageType.monthly);
  Package? get annual => pickPackage(offering, PackageType.annual);

  bool get hasProducts => monthly != null || annual != null;

  ProStatus copyWith({
    bool? isPro,
    bool? configured,
    Offering? offering,
    bool? loading,
    bool? purchasing,
    String? message,
    ProPlan? plan,
    bool? inTrial,
    bool clearMessage = false,
  }) =>
      ProStatus(
        plan: plan ?? this.plan,
        inTrial: inTrial ?? this.inTrial,
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

/// Opens the store's own subscription page.
///
/// Lives here rather than on the paywall because settings needs it too: the
/// paywall shows "you are on Plate Pro" to an existing subscriber, so sending
/// one there to change plan is a door into an empty room. Changing plan is the
/// store's job, and the only place proration is handled properly.
Future<void> openManageSubscriptions() async {
  final uri = Uri.parse(manageSubscriptionsUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Finds the monthly or annual package in an offering.
///
/// `Offering.monthly` and `Offering.annual` are only populated for packages
/// created with RevenueCat's reserved identifiers (`$rc_monthly`,
/// `\$rc_annual`). A package with any other lookup key lands in
/// `availablePackages` with `PackageType.custom`, and reading `offering.monthly`
/// returns null — which looks exactly like "no products configured" on the
/// paywall, with no way to tell the difference.
///
/// So: prefer the typed field, then fall back to reading the identifier. That
/// way the paywall works whether the packages were named RevenueCat's way or
/// the product's way.
Package? pickPackage(Offering? offering, PackageType wanted) {
  if (offering == null) return null;

  for (final package in offering.availablePackages) {
    if (package.packageType == wanted) return package;
  }

  final needles = wanted == PackageType.annual
      ? const ['annual', 'year']
      : const ['monthly', 'month'];
  for (final package in offering.availablePackages) {
    final id = package.identifier.toLowerCase();
    // "monthly" must not match "6monthly"; the typed check above already
    // caught the well-formed cases, so this only has to be sensible.
    if (needles.any(id.contains)) return package;
  }
  return null;
}

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

/// What the yearly plan saves against paying monthly, as words.
///
/// Worked out from the two prices the store actually reports rather than
/// written into the copy, because a hard-coded "save 50%" becomes a lie the
/// first time either price changes — and a wrong number about money is the
/// worst kind to ship. Null whenever it cannot be computed honestly, in which
/// case the card simply says nothing.
String? describeAnnualSaving(double? annual, double? monthly) {
  if (annual == null || monthly == null) return null;
  if (annual <= 0 || monthly <= 0) return null;

  final payingMonthly = monthly * 12;
  final saved = (1 - annual / payingMonthly) * 100;

  // Under a rounded 5% is not worth a line on the card, and anything at or
  // over 100 means the prices are nonsense.
  final percent = saved.round();
  if (percent < 5 || percent >= 100) return null;
  return 'Save $percent% against monthly';
}

/// Thin wrapper over the RevenueCat SDK. Kept behind an interface so widget
/// tests can run the whole app without touching the billing plugin.
abstract class PurchasesService {
  Future<ProStatus> init();

  Future<ProStatus> purchase(Package package);

  Future<ProStatus> restore();

  /// Pushes the store's own purchase state to RevenueCat and reads it back.
  ///
  /// The case this exists for: a code redeemed in the Play Store app rather
  /// than in here. The SDK does not hear about it, so the app goes on showing
  /// a paywall to someone who has already paid — and the only cure was
  /// Restore purchases, buried in settings, which nobody hunting for it has a
  /// reason to find.
  Future<ProStatus> sync();

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
        plan: _planOf(info),
        inTrial: _inTrial(info),
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
        plan: _planOf(result.customerInfo),
        inTrial: _inTrial(result.customerInfo),
        purchasing: false,
        message: _isEntitled(result.customerInfo) ? 'You are on Plate Pro.' : null,
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
  Future<ProStatus> sync() async {
    try {
      await Purchases.syncPurchases();
      final info = await Purchases.getCustomerInfo();
      _status = _status.copyWith(
        isPro: _isEntitled(info),
        plan: _planOf(info),
        inTrial: _inTrial(info),
      );
    } catch (_) {
      // Silent: this runs on every return to the foreground and must never
      // put an error in front of someone who was only switching apps.
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
        plan: _planOf(info),
        inTrial: _inTrial(info),
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

  /// Which plan the active entitlement came from.
  ///
  /// Read from the product id rather than the package, because the package is
  /// what was on offer at purchase time and the product is what the store says
  /// is running now. Unrecognised ids fall back to [ProPlan.none], which only
  /// costs the upgrade prompt — never access.
  ProPlan _planOf(CustomerInfo info) {
    final entitlement = info.entitlements.active[entitlementId];
    final product = entitlement?.productIdentifier ?? '';
    if (product.contains('annual') || product.contains('yearly')) return ProPlan.yearly;
    if (product.contains('month')) return ProPlan.monthly;
    return ProPlan.none;
  }

  /// True while the introductory period is running and nothing has been paid.
  bool _inTrial(CustomerInfo info) =>
      info.entitlements.active[entitlementId]?.periodType == PeriodType.trial;

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
  Future<ProStatus> sync() async => ProStatus(isPro: isPro, configured: false);

  @override
  Future<String?> appUserId() async => userId;
}
