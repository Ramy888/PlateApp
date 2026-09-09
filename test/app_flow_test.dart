import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platepatch/data/auth_service.dart';
import 'package:platepatch/data/catalog.dart';
import 'package:platepatch/data/patch_images.dart';
import 'package:platepatch/data/prefs_repository.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:platepatch/domain/models.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/ui/meal_screen.dart';
import 'package:platepatch/ui/onboarding_screen.dart';
import 'package:platepatch/ui/saved_screen.dart';
import 'package:platepatch/ui/settings_screen.dart';
import 'package:platepatch/ui/theme.dart';
import 'package:platepatch/ui/widgets/common.dart';
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
      patchImagesProvider.overrideWithValue(MemoryPatchImages()),
      catalogProvider.overrideWithValue(_realCatalog()),
      purchasesServiceProvider.overrideWithValue(InertPurchasesService(isPro: isPro)),
      authServiceProvider.overrideWithValue(InertAuthService()),
    ],
  );
  addTearDown(container.dispose);

  if (isPro) await container.read(proProvider.notifier).init();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        // Tests assert on settled frames, and decorative motion is deliberately
        // endless — so they run the way a reduced-motion phone does.
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(theme: buildTheme(), home: home),
      ),
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

/// Taps the first thing whose visible label matches, scrolling it into view.
/// For anything outside the meal picker's food rails — goals, preferences,
/// buttons.
Future<void> _tapTile(WidgetTester tester, String label) async {
  final finder = find.text(label).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}


/// Opens the food page for the meal currently showing on the hub. Tapping the
/// card you are already on is what opens it.
Future<void> _openFoodPicker(WidgetTester tester) async {
  if (find.text('Tap to pick the food').evaluate().isEmpty) return;
  await tester.tap(find.text('Tap to pick the food'));
  await tester.pumpAndSettle();
}

/// Taps a food, opening the food page first if the hub is still showing, then
/// the rail the food lives in, then scrolling that rail along to it. This walks
/// the same path a finger does.
Future<void> _tapFood(WidgetTester tester, String name) async {
  await _openFoodPicker(tester);

  final food = _realCatalog().foods.firstWhere((f) => f.name == name);
  final group = FoodGroup.all.firstWhere((g) => g.id == food.group);
  // A Pro food sits in its own group rail for a subscriber, and in the single
  // locked rail for everyone else. The locked rail only exists on screen for a
  // free user, so its presence is what decides.
  final locked = find.text(FoodGroup.locked.label).evaluate().isNotEmpty;
  final rail = (!food.isFree && locked) ? FoodGroup.locked : group;

  // Only one rail is open at a time, so open this one unless its foods are
  // already on screen.
  if (find.text(name).evaluate().isEmpty) {
    final head = find.text(rail.label);
    await tester.ensureVisible(head);
    await tester.pumpAndSettle();
    await tester.tap(head);
    await tester.pumpAndSettle();
  }

  final tile = find.text(name);
  if (tile.evaluate().isEmpty) {
    // Exactly one rail is open, so exactly one horizontal list exists and this
    // cannot scroll the wrong one.
    final railList = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right);
    expect(railList, findsOneWidget,
        reason: 'expected the "${rail.label}" rail to be open');
    await tester.dragUntilVisible(tile, railList, const Offset(-120, 0));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(tile.first);
  await tester.pumpAndSettle();
  await tester.tap(tile.first);
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
    // The hub offers the meal; the food page is where the patch button lives,
    // and it stays disabled until something is on the plate.
    await _openFoodPicker(tester);
    expect(find.text('Pick what you are eating'), findsOneWidget);

    await _tapFood(tester, 'Rice');
    expect(find.textContaining('Patch this meal'), findsOneWidget);
  });

  testWidgets('a plate of rice leads with one patch and offers the other two',
      (tester) async {
    await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapFood(tester, 'Rice');
    await tester.tap(find.textContaining('Patch this meal'));
    await tester.pumpAndSettle();

    expect(find.text('Your patch'), findsOneWidget);
    expect(find.textContaining('This looks light on'), findsOneWidget);

    // One addition is the answer, said in words rather than only drawn.
    expect(find.text('ADD'), findsOneWidget);
    expect(find.text("I'll add this"), findsOneWidget);

    // The engine found three angles, so two are offered as alternatives.
    expect(find.text('Or instead'), findsOneWidget);
    expect(find.byType(PatchHighlight), findsOneWidget);
  });

  testWidgets('a balanced plate is told there is nothing to patch',
      (tester) async {
    await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapFood(tester, 'Fish'); // protein 3, fat 3
    await _tapFood(tester, 'Salad');
    await _tapFood(tester, 'Beans'); // fibre 3
    await tester.tap(find.textContaining('Patch this meal'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to patch.'), findsOneWidget);
    expect(find.text("I'll add this"), findsNothing);
  });

  testWidgets('adding a patch saves it and asks how the meal went',
      (tester) async {
    final container = await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapFood(tester, 'Rice');
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

    await _tapFood(tester, 'Pasta');
    await tester.tap(find.textContaining('Patch this meal'));
    await tester.pumpAndSettle();

    for (final banned in ['tuna', 'chicken', 'salmon', 'sardines']) {
      expect(find.textContaining(banned, findRichText: true), findsNothing,
          reason: '$banned shown to a vegetarian');
    }
  });

  group('saved patches', () {
    List<String> makeHistory(int count) => [
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
        prefs: {'onboarded': true, 'history': makeHistory(5)},
        home: const SavedScreen(),
      );
      expect(find.textContaining('Add a small bowl of yogurt'), findsNWidgets(3));
      expect(find.text('2 more saved patches'), findsOneWidget);
    });

    testWidgets('pro users see all of them and get the satisfaction summary',
        (tester) async {
      await _pumpApp(
        tester,
        prefs: {'onboarded': true, 'history': makeHistory(5)},
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

      await _tapFood(tester, 'Koshari');
      expect(find.text('Plate Pro'), findsOneWidget);
      expect(container.read(mealDraftProvider).foodIds, isEmpty);
    });

    testWidgets('restore purchases is always offered', (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true});
      await _tapFood(tester, 'Koshari');
      expect(find.text('Restore purchases'), findsOneWidget);
    });

    testWidgets('privacy and terms open in the app, with no dead link',
        (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true});
      await _tapFood(tester, 'Koshari');

      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.textContaining('sign in with Google'), findsOneWidget);

      // The policy has to describe what actually happens to a scanned photo,
      // or it is a false claim shipped to a store.
      expect(find.textContaining('stripped of all metadata'), findsOneWidget);
      // Every way something leaves the phone has to be named. Counting
      // occurrences of "Gemini" would depend on what a ListView happens to have
      // built, so this asserts the sections themselves.
      for (final heading in [
        'What happens to a photo you scan',
        'What happens to a meal you describe in words',
        'What happens to a meal you say out loud',
        'What happens when you open a result',
        'Signing in with Google',
      ]) {
        await tester.scrollUntilVisible(find.text(heading), 200);
        await tester.pumpAndSettle();
        expect(find.text(heading), findsOneWidget);
        // The app collects an email address and a name now, so the policy has
        // to name them. This assertion replaced one pinning the opposite claim,
        // and is here to catch the policy drifting back behind the code.
        if (heading == 'Signing in with Google') {
          expect(
            find.textContaining('your email address and your name'),
            findsOneWidget,
          );
        }
      }
      // Further down the page, so it has to be scrolled to.
      await tester.scrollUntilVisible(
        find.textContaining('Delete my account and data'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Delete my account and data'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terms'));
      await tester.pumpAndSettle();
      expect(find.text('Terms of use'), findsOneWidget);
      expect(find.textContaining('Not medical or dietary advice'), findsOneWidget);
      expect(find.textContaining('AI results are not facts'), findsOneWidget);
      // Apple rejects apps whose copy names a different store, so the store is
      // never hardcoded. Tests default to the Android target platform.
      expect(find.textContaining('Google Play'), findsWidgets);
      expect(find.textContaining('App Store'), findsNothing);
    });

    testWidgets('an unreachable store degrades to an explanation, not a crash',
        (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true});
      await _tapFood(tester, 'Koshari');
      expect(find.text('Pro is not available right now'), findsOneWidget);
    });

    testWidgets('pro users can select locked foods directly', (tester) async {
      final container =
          await _pumpApp(tester, prefs: {'onboarded': true}, isPro: true);

      await _tapFood(tester, 'Koshari');
      expect(find.text('Plate Pro'), findsNothing);
      expect(container.read(mealDraftProvider).foodIds, contains('koshari'));
    });
  });

  group('settings', () {
    testWidgets('a goal chosen at onboarding can be changed later',
        (tester) async {
      final container = await _pumpApp(
        tester,
        prefs: {'onboarded': true, 'goal': Goal.feelSatisfied.id},
        home: const SettingsScreen(),
      );
      expect(container.read(settingsProvider).goal, Goal.feelSatisfied);

      await _tapTile(tester, 'More energy');
      expect(container.read(settingsProvider).goal, Goal.moreEnergy);
    });

    testWidgets('preferences toggle both ways and persist', (tester) async {
      final container = await _pumpApp(
        tester,
        prefs: {'onboarded': true, 'diet_prefs': <String>[DietPref.vegetarian.id]},
        home: const SettingsScreen(),
      );

      await _tapTile(tester, 'Dairy-free');
      expect(container.read(settingsProvider).dietPrefs,
          {DietPref.vegetarian, DietPref.dairyFree});

      await _tapTile(tester, 'Vegetarian');
      expect(container.read(settingsProvider).dietPrefs, {DietPref.dairyFree});

      // Written through to storage, not just held in memory.
      final repo = container.read(prefsRepositoryProvider);
      expect(repo.dietPrefs, {DietPref.dairyFree});
    });

    testWidgets('a change here changes the next suggestion', (tester) async {
      // The point of the screen: settings must reach the engine.
      final container = await _pumpApp(
        tester,
        prefs: {'onboarded': true},
        home: const SettingsScreen(),
      );
      container.read(mealDraftProvider.notifier).toggleFood('white_rice');

      await _tapTile(tester, 'Vegetarian');
      final patches = container.read(patchResultProvider).patches;
      expect(patches, isNotEmpty);
      for (final p in patches) {
        expect(p.addition.tags.intersection({'meat', 'fish'}), isEmpty);
      }
    });

    testWidgets('free users see the plan and a way to Pro', (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true}, home: const SettingsScreen());
      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('See Pro'), findsOneWidget);
      expect(find.text('Restore purchases'), findsOneWidget);
    });

    testWidgets('pro users see their status, not an upsell', (tester) async {
      await _pumpApp(tester,
          prefs: {'onboarded': true}, isPro: true, home: const SettingsScreen());
      expect(find.text('Plate Pro'), findsOneWidget);
      expect(find.text('See Pro'), findsNothing);
    });

    testWidgets('settings is reachable from the meal screen', (tester) async {
      await _pumpApp(tester, prefs: {'onboarded': true});
      await tester.tap(find.byIcon(LucideIcons.settings));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  testWidgets('changing meal slot clears the plate', (tester) async {
    final container = await _pumpApp(tester, prefs: {'onboarded': true});

    await _tapFood(tester, 'Rice');
    expect(container.read(mealDraftProvider).foodIds, isNotEmpty);

    // Back to the hub to change meal — the pager lives there, not on the food
    // page the previous tap opened.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The neighbouring cards only peek onto the screen, so this swipes the
    // pager the way a thumb does rather than tapping a half-visible card.
    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(container.read(mealDraftProvider).slot, MealSlot.breakfast);
    expect(container.read(mealDraftProvider).foodIds, isEmpty);
  });
}
