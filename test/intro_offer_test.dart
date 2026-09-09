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

  group('describeAnnualSaving', () {
    test('states the real saving off the two real prices', () {
      // The shipped pair: $11.99 a year against $1.99 a month.
      expect(describeAnnualSaving(11.99, 1.99), 'Save 50% against monthly');
    });

    test('a three-day trial reads correctly on the monthly card', () {
      expect(describeIntroOffer(3, PeriodUnit.day), '3 days free');
    });

    test('says nothing rather than something wrong', () {
      expect(describeAnnualSaving(null, 1.99), isNull);
      expect(describeAnnualSaving(11.99, null), isNull);
      expect(describeAnnualSaving(0, 1.99), isNull);
      expect(describeAnnualSaving(11.99, 0), isNull);
      // A yearly plan priced above twelve months of monthly saves nothing.
      expect(describeAnnualSaving(30.00, 1.99), isNull);
      // And a saving too small to be worth a line stays off the card.
      expect(describeAnnualSaving(23.00, 1.99), isNull);
    });

    test('a saving that rounds to 100% is a mispriced plan, not a bargain', () {
      // 5 cents a year against $1.99 a month is 99.8%, which rounds to 100 —
      // and "Save 100% against monthly" on a plan that still charges is the
      // sort of claim that gets an app pulled. (Zero is caught earlier, by the
      // price check, so this is the only input that reaches that guard.)
      expect(describeAnnualSaving(0.05, 1.99), isNull);
    });
  });
}
