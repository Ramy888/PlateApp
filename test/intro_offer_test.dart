import 'package:flutter_test/flutter_test.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show PeriodUnit;

void main() {
  group('describeIntroOffer', () {
    test('reads a day-based trial as days', () {
      expect(describeIntroOffer(7, PeriodUnit.day), '7 days free');
    });

    test('does not turn a one-week trial into "1 day"', () {
      // The bug this guards: Play reports P1W as 1 unit of "week". Formatting
      // the count without the unit advertised a 1-day trial for a 7-day one.
      expect(describeIntroOffer(1, PeriodUnit.week), '1 week free');
    });

    test('handles months and years', () {
      expect(describeIntroOffer(3, PeriodUnit.month), '3 months free');
      expect(describeIntroOffer(1, PeriodUnit.year), '1 year free');
    });

    test('says nothing when there is no offer to describe', () {
      expect(describeIntroOffer(null, null), isNull);
      expect(describeIntroOffer(0, PeriodUnit.day), isNull);
      expect(describeIntroOffer(7, PeriodUnit.unknown), isNull);
      expect(describeIntroOffer(7, null), isNull);
    });
  });
}
