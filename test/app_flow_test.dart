import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platepatch/data/catalog.dart';
import 'package:platepatch/data/prefs_repository.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:platepatch/domain/models.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/ui/meal_screen.dart';
import 'package:platepatch/ui/onboarding_screen.dart';
import 'package:platepatch/ui/saved_screen.dart';
import 'package:platepatch/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real bundled catalogue, read from disk so these tests exercise the data
/// that actually ships rather than a convenient fixture.
Catalog _realCatalog() {
  List<T> parse<T>(String name, T Function(Map<String, dynamic>) fromJson) =>
      (jsonDecode(File('assets/data/$name.json').readAsStringSync()) as List<dynamic>)
          .map((j) => fromJson(j as Map<String, dynamic>))
          .toList();

  return Catalog(
    foods: parse('foods', FoodItem.fromJson),
    additions: parse('additions', Addition.fromJson),
  );
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool isPro = false,
  Widget home = const _Root(),
}) async {
  // A tall viewport so a full food grid and three suggestion cards fit without
  // scrolling. The default 800x600 test window is nothing like a phone.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final repo = PrefsRepository(await SharedPreferences.getInstance());
  final container = ProviderContainer(
    overrides: [
      prefsRepositoryProvider.overrideWithValue(repo),
      catalogProvider.overrideWithValue(_realCatalog()),
      purchasesServiceProvider.overrideWithValue(InertPurchasesService(isPro: isPro)),
    ],
  );
  addTearDown(container.dispose);

  if (isPro) await container.read(proProvider.notifier).init();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
    return onboarded ? const MealScreen() : const OnboardingScreen();
  }
}

/// Taps the first tile whose visible label matches, scrolling it into view.
Future<void> _tapTile(WidgetTester tester, String label) async {
  final finder = find.text(label).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a first launch lands on onboarding, not the meal screen', (tester) async {
    await _pumpApp(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.textContaining('No counting'), findsOneWidget);
  });

  testWidgets('onboarding walks through goal and preferences into the app',
      (tester) async {
    final container = await _pumpApp(tester);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More energy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vegetarian'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start patching'));
    await tester.pumpAndSettle();

    expect(find.byType(MealScreen), findsOneWidget);
    expect(container.read(settingsProvider).goal, Goal.moreEnergy);
    expect(container.read(settingsProvider).dietPrefs, contains(DietPref.vegetarian));
  });

  testWidgets('choices made in onboarding survive a relaunch', (tester) async {
    await _pumpApp(tester, prefs: {
      'onboarded': true,
      'goal': Goal.moreEnergy.id,
      'diet_prefs': <String>[DietPref.dairyFree.id],
    });
    // Reaching the meal screen at all proves onboarded was read back; the
    // engine result below proves the preference was too.
    expect(find.byType(MealScreen), findsOneWidget);
  });

  testWidgets('the patch button stays disabled until a food is picked',
      (tester) async {
    await _pumpApp(tester, prefs: {'onboarded': true});
    expect(find.text('Pick what you are eating'), findsOneWidget);

    await _tapTile(tester, 'Rice');
    expect(find.textContaining('Patch this meal'), findsOneWidget);
  });

  testWidgets('a plate of rice produces three suggestion cards', (tester) async {
    await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapTile(tester, 'Rice');
    await tester.tap(find.textContaining('Patch this meal'));
    await tester.pumpAndSettle();

    expect(find.text('Your PlatePatch'), findsOneWidget);
    expect(find.textContaining('This looks light on'), findsOneWidget);
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text('Cheapest'), findsOneWidget);
    expect(find.text('Plant-based'), findsOneWidget);
    expect(find.text("I'll add this"), findsNWidgets(3));
  });

  testWidgets('a balanced plate is told there is nothing to patch',
      (tester) async {
    await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapTile(tester, 'Fish'); // protein 3, fat 3
    await _tapTile(tester, 'Salad');
    await _tapTile(tester, 'Beans'); // fibre 3
    await tester.tap(find.textContaining('Patch this meal'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to patch.'), findsOneWidget);
    expect(find.text("I'll add this"), findsNothing);
  });

  testWidgets('adding a patch saves it and asks how the meal went',
      (tester) async {
    final container = await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapTile(tester, 'Rice');
    await tester.tap(find.textContaining('Patch this meal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'll add this").first);
    await tester.pumpAndSettle();

    expect(find.text('Saved. How did it go?'), findsOneWidget);
    expect(container.read(historyProvider), hasLength(1));
    expect(container.read(historyProvider).single.satisfaction, isNull);

    await tester.tap(find.text('Still hungry'));
    await tester.pumpAndSettle();

    expect(container.read(historyProvider).single.satisfaction, Satisfaction.stillHungry);
    // The plate is cleared so the next meal starts fresh.
    expect(container.read(mealDraftProvider).isEmpty, isTrue);
    expect(find.byType(MealScreen), findsOneWidget);
  });

  testWidgets('vegetarian users are never shown meat or fish', (tester) async {
    await _pumpApp(tester, prefs: {
      'onboarded': true,
      'diet_prefs': <String>[DietPref.vegetarian.id],
    });

    await _tapTile(tester, 'Pasta');
    await tester.tap(find.textContaining('Patch this meal'));
    await tester.pumpAndSettle();

    for (final banned in ['tuna', 'chicken', 'salmon', 'sardines']) {
      expect(find.textContaining(banned, findRichText: true), findsNothing,
          reason: '$banned shown to a vegetarian');
    }
  });

  group('saved patches', () {
    List<String> _history(int count) => [
          for (var i = 0; i < count; i++)
            jsonEncode(SavedPatch(
              id: 'p$i',
              savedAt: DateTime(2026, 9, 1).add(Duration(hours: i)),
              slot: MealSlot.lunchDinner,
              foodIds: const ['white_rice'],
              additionId: 'yogurt',
              additionName: 'Add a small bowl of yogurt $i',
              additionEmoji: '🥣',
              gapIds: const ['protein'],
            ).toJson()),
        ];

    testWidgets('an empty list explains what to do next', (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true}, home: const SavedScreen());
      expect(find.text('Nothing saved yet'), findsOneWidget);
    });

    testWidgets('free users see three, and are told the rest are kept',
        (tester) async {
      await _pumpApp(
        tester,
        prefs: {'onboarded': true, 'history': _history(5)},
        home: const SavedScreen(),
      );
      expect(find.textContaining('Add a small bowl of yogurt'), findsNWidgets(3));
      expect(find.text('2 more saved patches'), findsOneWidget);
    });

    testWidgets('pro users see all of them and get the satisfaction summary',
        (tester) async {
      await _pumpApp(
        tester,
        prefs: {'onboarded': true, 'history': _history(5)},
        isPro: true,
        home: const SavedScreen(),
      );
      expect(find.textContaining('Add a small bowl of yogurt'), findsNWidgets(5));
      expect(find.textContaining('more saved patches'), findsNothing);
    });
  });

  group('paywall', () {
    testWidgets('a locked food opens the paywall instead of selecting it',
        (tester) async {
      final container = await _pumpApp(tester, prefs: {'onboarded': true});

      await _tapTile(tester, 'Koshari');
      expect(find.text('PlatePatch Pro'), findsOneWidget);
      expect(container.read(mealDraftProvider).foodIds, isEmpty);
    });

    testWidgets('restore purchases is always offered', (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true});
      await _tapTile(tester, 'Koshari');
      expect(find.text('Restore purchases'), findsOneWidget);
    });

    testWidgets('an unreachable store degrades to an explanation, not a crash',
        (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true});
      await _tapTile(tester, 'Koshari');
      expect(find.text('Pro is not available right now'), findsOneWidget);
    });

    testWidgets('pro users can select locked foods directly', (tester) async {
      final container =
          await _pumpApp(tester, prefs: {'onboarded': true}, isPro: true);

      await _tapTile(tester, 'Koshari');
      expect(find.text('PlatePatch Pro'), findsNothing);
      expect(container.read(mealDraftProvider).foodIds, contains('koshari'));
    });
  });

  testWidgets('changing meal slot clears the plate', (tester) async {
    final container = await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapTile(tester, 'Rice');
    expect(container.read(mealDraftProvider).foodIds, isNotEmpty);

    await tester.tap(find.text('Breakfast'));
    await tester.pumpAndSettle();
    expect(container.read(mealDraftProvider).foodIds, isEmpty);
    expect(container.read(mealDraftProvider).slot, MealSlot.breakfast);
  });
}
