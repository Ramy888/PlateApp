# The Plate

**Add one simple thing to the meal you already have.**

The Plate answers a single question: what small addition would make this meal
more satisfying? Not what to cut out, not what to weigh, not how many calories
are in it. One practical addition — a boiled egg, a scoop of hummus, a side
salad — and three ways to get there.

No calorie counting. No weighing. No food diary. No account. No server.

---

## How it works

1. Pick a meal slot: breakfast, lunch or dinner, or a snack.
2. Tap what is on the plate. Rough is fine.
3. The Plate works out what the meal is light on — protein, fibre, or healthy
   fats — and offers three additions that close the gap: the **fastest**, the
   **cheapest**, and a **plant-based** one.
4. Afterwards, one tap: still hungry, comfortably satisfied, or too full. That
   single answer is the only thing the app learns from.

## Architecture

```
lib/
  domain/
    models.dart        Nutrients, meal slots, goals, preferences, saved patches
    patch_engine.dart  The recommendation engine — pure, deterministic Dart
  data/
    catalog.dart          Loads the bundled JSON food catalogue
    prefs_repository.dart On-device persistence (shared_preferences)
    purchases_service.dart RevenueCat, behind an interface
  state/providers.dart  Riverpod wiring
  ui/                   Six screens and the shared widgets
assets/data/
  foods.json            51 foods, free and Pro collections
  additions.json        30 additions, free and Pro collections
```

The whole recommendation is a pure function of `(meal slot, foods, goal,
preferences, recent history, Pro status)`. That is what makes it testable, and
what makes a demo reproducible: the same plate always gives the same answer.

### The engine, briefly

Foods and additions carry coarse 0–3 scores for protein, fibre and healthy fat.
A plate below the threshold for a nutrient has a **gap**. Gaps are ranked by
severity, weighted by the user's goal and nudged by their recent after-meal
checks. Candidate additions are filtered by meal slot, dietary preferences and
tier, then scored on how much of the ranked gaps they actually close —
contribution beyond what a gap needs counts for nothing, so a protein bomb never
wins a fibre gap. The most constrained angle (plant-based) picks first, so a thin
candidate list never leaves that card empty or mislabelled.

## Running it

```bash
flutter pub get
flutter run
```

Purchases are inert without a RevenueCat key, and the app is fully usable that
way — the paywall reports that Pro is unavailable and nothing else changes.

```bash
flutter run --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
```

## Tests

```bash
flutter test        # 121 tests
```

Three layers:

- **`patch_engine_test.dart`** — the rules, on a hand-built catalogue where each
  test controls one variable.
- **`catalog_data_test.dart`** — the JSON that actually ships. Every meal slot ×
  goal combination must yield three distinct cards, and all 16 preference
  combinations × 3 slots must yield at least one honest suggestion. A catalogue
  edit that dead-ends a vegetarian, dairy-free, gluten-free, low-cost user fails
  here rather than in the store.
- **`app_flow_test.dart`** — the real screens, driven end to end against the real
  catalogue: onboarding, patching, saving, the after-meal check, the free save
  limit, and every paywall entry point.

## Design

Tokens, components and a paste-ready prompt for every screen are in
[`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md), with a rendered visual reference linked
from it. `lib/ui/theme.dart` remains the source of truth.

## Release

Signing, Play Console, RevenueCat and the store listing are documented in
[`SETUP.md`](SETUP.md). Listing copy is in [`STORE_LISTING.md`](STORE_LISTING.md).

```bash
flutter build appbundle --release --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
dart run tool/generate_icon.dart   # icon + adaptive layers + feature graphic
./tool/capture_screens.sh          # store screenshots from a running emulator
```

`android/key.properties` and the keystore are gitignored. **Back them up** —
losing them means never being able to update the app.

## Deliberate omissions

No camera scanning, no barcodes, no AI, no recipes, no accounts, no cloud sync,
no meal-plan generation, no streaks, no notifications. Each of those would make
The Plate a different, worse app.
