import 'package:flutter_test/flutter_test.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Building a real [Package] needs a real [StoreProduct], so these go through
/// the JSON constructors the SDK uses when decoding a response.
/// The SDK decodes packageType from UPPER_SNAKE on the wire, not the Dart enum
/// name — an easy thing to get wrong in a fixture and then "prove" the wrong
/// behaviour.
String wire(PackageType type) => switch (type) {
      PackageType.monthly => 'MONTHLY',
      PackageType.annual => 'ANNUAL',
      PackageType.lifetime => 'LIFETIME',
      PackageType.custom => 'CUSTOM',
      _ => 'UNKNOWN',
    };

Map<String, dynamic> pkg(String identifier, PackageType type) => {
      'identifier': identifier,
      'packageType': wire(type),
      'product': {
        'identifier': identifier,
        'description': '',
        'title': identifier,
        'price': 1.99,
        'priceString': r'$1.99',
        'currencyCode': 'USD',
      },
      'presentedOfferingContext': {
        'offeringIdentifier': 'default',
        'placementIdentifier': null,
        'targetingContext': null,
      },
    };

Offering offering(List<Map<String, dynamic>> packages) => Offering.fromJson({
      'identifier': 'default',
      'serverDescription': '',
      'metadata': <String, dynamic>{},
      'availablePackages': packages,
    });

void main() {
  group('finding the monthly and annual packages', () {
    test('uses the typed field when RevenueCat set it', () {
      final o = offering([
        pkg(r'$rc_monthly', PackageType.monthly),
        pkg(r'$rc_annual', PackageType.annual),
      ]);
      expect(pickPackage(o, PackageType.monthly)?.identifier, r'$rc_monthly');
      expect(pickPackage(o, PackageType.annual)?.identifier, r'$rc_annual');
    });

    test('falls back to the identifier for custom lookup keys', () {
      // This is the real project's shape: packages named after the products
      // rather than with RevenueCat's reserved identifiers. Reading
      // offering.monthly here returns null, and the paywall would say
      // "Pro is not available right now" with everything configured correctly.
      final o = offering([
        pkg('platepatch_pro_monthly', PackageType.custom),
        pkg('platepatch_pro_yearly', PackageType.custom),
      ]);
      expect(pickPackage(o, PackageType.monthly)?.identifier, 'platepatch_pro_monthly');
      expect(pickPackage(o, PackageType.annual)?.identifier, 'platepatch_pro_yearly');
    });

    test('prefers a properly typed package over a name match', () {
      final o = offering([
        pkg('some_monthly_thing', PackageType.custom),
        pkg(r'$rc_monthly', PackageType.monthly),
      ]);
      expect(pickPackage(o, PackageType.monthly)?.identifier, r'$rc_monthly');
    });

    test('returns null rather than guessing when nothing fits', () {
      final o = offering([pkg('lifetime_forever', PackageType.custom)]);
      expect(pickPackage(o, PackageType.monthly), isNull);
      expect(pickPackage(o, PackageType.annual), isNull);
    });

    test('handles an offering with no packages, and no offering at all', () {
      expect(pickPackage(offering([]), PackageType.monthly), isNull);
      expect(pickPackage(null, PackageType.annual), isNull);
    });
  });
}
