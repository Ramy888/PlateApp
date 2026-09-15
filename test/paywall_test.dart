import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Offering, Package;
import 'package:platepatch/data/purchases_service.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/ui/paywall_screen.dart';
import 'package:platepatch/ui/theme.dart';

/// One package, shaped the way the store sends them.
Map<String, dynamic> _package(String id, String type, double price, String shown) => {
      'identifier': id,
      'packageType': type,
      'product': {
        'identifier': 'platepatch_pro_${type.toLowerCase()}',
        'description': 'Plate Pro',
        'title': 'Plate Pro',
        'price': price,
        'priceString': shown,
        'currencyCode': 'USD',
        'productCategory': 'SUBSCRIPTION',
      },
      'presentedOfferingContext': {
        'offeringIdentifier': 'default',
        'placementIdentifier': null,
        'targetingContext': null,
      },
    };

Offering _offering() {
  final monthly = _package(r'$rc_monthly', 'MONTHLY', 4.99, r'$4.99');
  final annual = _package(r'$rc_annual', 'ANNUAL', 39.99, r'$39.99');
  return Offering.fromJson({
    'identifier': 'default',
    'serverDescription': 'Plate Pro',
    'metadata': <String, Object>{},
    'availablePackages': [monthly, annual],
    'monthly': monthly,
    'annual': annual,
  });
}

/// A store with both plans on the shelf.
class StockedStore implements PurchasesService {
  StockedStore({this.isPro = false});

  final bool isPro;

  @override
  Future<ProStatus> init() async =>
      ProStatus(isPro: isPro, configured: true, offering: _offering());

  @override
  Future<ProStatus> purchase(Package package) async => init();

  @override
  Future<ProStatus> restore() async => init();

  @override
  Future<String?> appUserId() async => 'rcu_test';
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(1080, 2400),
  double dpr = 3.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    purchasesServiceProvider.overrideWithValue(StockedStore()),
  ]);
  addTearDown(container.dispose);
  await container.read(proProvider.notifier).init();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(),
        home: const PaywallScreen(reason: 'More AI meal chats'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Whether a widget is inside the visible window, not merely in the tree.
bool _onScreen(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final top = box.localToGlobal(Offset.zero).dy;
  final bottom = top + box.size.height;
  final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  return top >= 0 && bottom <= screen;
}

void main() {
  group('the paywall', () {
    testWidgets('shows both prices without scrolling', (tester) async {
      // The prices used to sit at the foot of a list of seven benefits, so the
      // one thing this screen exists to ask had to be scrolled to. A buy button
      // that is visible while its price is not asks people to commit to a
      // number they cannot see.
      await _pump(tester);

      expect(find.text(r'$4.99'), findsOneWidget);
      expect(find.text(r'$39.99'), findsOneWidget);
      expect(_onScreen(tester, find.text(r'$4.99')), isTrue,
          reason: 'the monthly price must be on screen at rest');
      expect(_onScreen(tester, find.text(r'$39.99')), isTrue,
          reason: 'the yearly price must be on screen at rest');
    });

    testWidgets('still shows them on a short screen', (tester) async {
      // A small phone is where a scrolled-off price actually bites.
      await _pump(tester, size: const Size(1080, 1920), dpr: 3.0);

      expect(_onScreen(tester, find.text(r'$4.99')), isTrue);
      expect(_onScreen(tester, find.text(r'$39.99')), isTrue);
    });

    testWidgets('the buy button is visible alongside the prices', (tester) async {
      await _pump(tester);

      final buy = find.byType(FilledButton);
      expect(buy, findsOneWidget);
      expect(_onScreen(tester, buy), isTrue);
    });

    testWidgets('the benefits still scroll behind them', (tester) async {
      // Pinning the prices must not cost the reasons to buy: they move into a
      // scroller above, rather than off the screen.
      await _pump(tester);
      expect(find.text('Plate Pro'), findsWidgets);

      final list = find.byType(ListView);
      expect(list, findsOneWidget);
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();

      // Scrolling the reasons must not take the prices with them.
      expect(_onScreen(tester, find.text(r'$4.99')), isTrue);
      expect(_onScreen(tester, find.text(r'$39.99')), isTrue);
    });
  });
}
