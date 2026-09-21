import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../data/catalog.dart';
import '../data/prefs_repository.dart';
import '../data/auth_service.dart';
import '../data/patch_images.dart';
import '../data/purchases_service.dart';
import '../data/voice_service.dart';
import '../domain/models.dart';
import '../domain/patch_engine.dart';
import 'scan_providers.dart';

/// These three are resolved before `runApp` and injected as overrides, which
/// keeps the rest of the app free of `AsyncValue` plumbing for things that are
/// always ready by the time a widget builds.
final prefsRepositoryProvider = Provider<PrefsRepository>(
  (ref) => throw StateError('prefsRepositoryProvider must be overridden at startup'),
);

final catalogProvider = Provider<Catalog>(
  (ref) => throw StateError('catalogProvider must be overridden at startup'),
);

final purchasesServiceProvider = Provider<PurchasesService>(
  (ref) => throw StateError('purchasesServiceProvider must be overridden at startup'),
);

final patchEngineProvider = Provider<PatchEngine>(
  (ref) => PatchEngine(additions: ref.watch(catalogProvider).additions),
);

// ---------------------------------------------------------------- settings

class AppSettings {
  const AppSettings({
    required this.onboarded,
    required this.goal,
    required this.dietPrefs,
  });

  final bool onboarded;
  final Goal goal;
  final Set<DietPref> dietPrefs;

  AppSettings copyWith({bool? onboarded, Goal? goal, Set<DietPref>? dietPrefs}) => AppSettings(
        onboarded: onboarded ?? this.onboarded,
        goal: goal ?? this.goal,
        dietPrefs: dietPrefs ?? this.dietPrefs,
      );
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final repo = ref.watch(prefsRepositoryProvider);
    return AppSettings(
      onboarded: repo.onboarded,
      goal: repo.goal,
      dietPrefs: repo.dietPrefs,
    );
  }

  PrefsRepository get _repo => ref.read(prefsRepositoryProvider);

  Future<void> setGoal(Goal goal) async {
    state = state.copyWith(goal: goal);
    await _repo.setGoal(goal);
  }

  Future<void> togglePref(DietPref pref) async {
    final next = {...state.dietPrefs};
    next.contains(pref) ? next.remove(pref) : next.add(pref);
    state = state.copyWith(dietPrefs: next);
    await _repo.setDietPrefs(next);
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboarded: true);
    await _repo.setOnboarded(true);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

// ----------------------------------------------------------------- history

class HistoryController extends Notifier<List<SavedPatch>> {
  @override
  List<SavedPatch> build() => ref.watch(prefsRepositoryProvider).history;

  PrefsRepository get _repo => ref.read(prefsRepositoryProvider);

  Future<void> save(SavedPatch patch) async {
    state = [patch, ...state];
    await _repo.setHistory(state);
  }

  Future<void> recordSatisfaction(String id, Satisfaction satisfaction) async {
    state = [
      for (final p in state) p.id == id ? p.withSatisfaction(satisfaction) : p,
    ];
    await _repo.setHistory(state);
  }

  Future<void> remove(String id) async {
    // The picture goes with the patch. Leaving orphaned files behind would be a
    // slow leak of exactly the thing this app promises to keep small.
    final going = state.where((p) => p.id == id).firstOrNull;
    state = state.where((p) => p.id != id).toList();
    await _repo.setHistory(state);
    await ref.read(patchImagesProvider).remove(going?.imagePath);
  }

  /// Used by "Delete my data". Empties the list in memory as well as on disk,
  /// so the UI reflects it without a restart.
  Future<void> clear() async {
    state = const [];
    await _repo.setHistory(const []);
    await ref.read(patchImagesProvider).clear();
  }
}

final historyProvider =
    NotifierProvider<HistoryController, List<SavedPatch>>(HistoryController.new);

/// Free users see their three most recent saves. The rest are kept on the
/// device and reappear on upgrade — nothing is ever deleted behind a paywall.
final visibleHistoryProvider = Provider<List<SavedPatch>>((ref) {
  final all = ref.watch(historyProvider);
  final isPro = ref.watch(proProvider).isPro;
  return isPro ? all : all.take(PrefsRepository.freeSavedLimit).toList();
});

final lockedHistoryCountProvider = Provider<int>((ref) {
  final all = ref.watch(historyProvider).length;
  final visible = ref.watch(visibleHistoryProvider).length;
  return all - visible;
});

/// Recent after-meal checks, turned into the nudge the engine applies.
final historyInsightProvider = Provider<HistoryInsight>(
  (ref) => HistoryInsight.fromHistory(ref.watch(historyProvider)),
);

// --------------------------------------------------------------------- pro

class ProController extends Notifier<ProStatus> {
  @override
  ProStatus build() => const ProStatus();

  PurchasesService get _service => ref.read(purchasesServiceProvider);

  Future<void> init() async {
    state = await _service.init();
    // Someone who subscribed on an older build has a server that still has no
    // RevenueCat id to check them against, and they will never tap buy or
    // restore again — they have already paid. This is the only thing that
    // repairs them, so it runs on every launch that finds a subscription.
    await _tellTheServer();
  }

  Future<void> buy(Package package) async {
    state = state.copyWith(purchasing: true, clearMessage: true);
    state = await _service.purchase(package);
    await _tellTheServer();
  }

  /// When the last sync ran, so returning to the foreground repeatedly does
  /// not mean a RevenueCat round trip per app switch.
  DateTime? _syncedAt;

  /// Re-reads the store, for purchases made outside the app.
  ///
  /// Called when the app comes back to the foreground, which is exactly the
  /// moment someone returns from redeeming a code in the Play Store. Cheap to
  /// skip and expensive to spam, so it is rate limited rather than guarded by
  /// a flag someone has to remember to set.
  Future<void> sync() async {
    final now = DateTime.now();
    final last = _syncedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _syncedAt = now;

    final was = state.isPro;
    state = await _service.sync();
    // Only when it changes: the server is the one that has to be told, and
    // telling it on every resume would be a request per app switch.
    if (state.isPro && !was) await _tellTheServer();
  }

  Future<void> restore() async {
    state = state.copyWith(purchasing: true, clearMessage: true);
    state = await _service.restore();
    await _tellTheServer();
  }

  /// The phone knowing it is Pro is not the same as being able to use Pro.
  ///
  /// Every paid feature is gated by the server's own allowance, and the server
  /// verifies with RevenueCat rather than believing the app. Until it is told
  /// to look again it keeps serving the free tier — which is how someone with
  /// a Google receipt in their inbox ends up being sent back to the paywall.
  Future<void> _tellTheServer() async {
    if (!state.isPro) return;
    await ref.read(scanControllerProvider.notifier).onEntitlementChanged();
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);
}

final proProvider = NotifierProvider<ProController, ProStatus>(ProController.new);

// ------------------------------------------------------------- meal draft

/// What the user is building right now. Session-only: a half-finished meal is
/// not worth persisting, and restoring one would be confusing.
class MealDraft {
  const MealDraft({
    this.slot = MealSlot.lunchDinner,
    this.foodIds = const {},
    this.slotChosen = false,
  });

  final MealSlot slot;
  final Set<String> foodIds;

  /// Whether the user has actually picked a meal, as opposed to the default
  /// the rest of the app needs a concrete value for. The picker keeps the food
  /// rails closed until they have — thirty tiles before you have said what
  /// meal it is answers a question nobody asked.
  final bool slotChosen;

  bool get isEmpty => foodIds.isEmpty;

  MealDraft copyWith({MealSlot? slot, Set<String>? foodIds, bool? slotChosen}) =>
      MealDraft(
        slot: slot ?? this.slot,
        foodIds: foodIds ?? this.foodIds,
        slotChosen: slotChosen ?? this.slotChosen,
      );
}

class MealDraftController extends Notifier<MealDraft> {
  @override
  MealDraft build() => const MealDraft();

  /// Changing meal clears the plate: "rice" at dinner and "rice" at breakfast
  /// are not the same selection, and keeping stale tiles reads as a bug.
  void setSlot(MealSlot slot) => state = MealDraft(slot: slot, slotChosen: true);

  /// Replaces the plate wholesale.
  ///
  /// The scan result screen edits the meal and the suggestion in the same
  /// place, so the draft has to follow the recognised foods on every tap
  /// rather than once at a confirm step that no longer exists.
  void setFoods(Iterable<String> ids) =>
      state = state.copyWith(foodIds: ids.toSet());

  void toggleFood(String id) {
    final next = {...state.foodIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(foodIds: next);
  }

  void reset() => state = const MealDraft();
}

final mealDraftProvider = NotifierProvider<MealDraftController, MealDraft>(MealDraftController.new);

/// The whole recommendation, recomputed whenever anything it depends on moves.
final patchResultProvider = Provider<PatchResult>((ref) {
  final draft = ref.watch(mealDraftProvider);
  final settings = ref.watch(settingsProvider);
  final catalog = ref.watch(catalogProvider);
  return ref.watch(patchEngineProvider).patch(
        slot: draft.slot,
        foods: catalog.foodsByIds(draft.foodIds),
        goal: settings.goal,
        prefs: settings.dietPrefs,
        insight: ref.watch(historyInsightProvider),
        isPro: ref.watch(proProvider).isPro,
      );
});

/// The microphone and the speaker. Overridden in tests, which have neither.
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = DeviceVoiceService();
  ref.onDispose(service.dispose);
  return service;
});

/// Pictures of saved patches, on this device only.
final patchImagesProvider = Provider<PatchImages>((ref) => const DevicePatchImages());

/// Google sign-in. Overridden in tests, which have no Google account.
final authServiceProvider = Provider<AuthService>((ref) => GoogleAuthService(
      // The *web* client. The three Android client ids are never named in code.
      serverClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
        defaultValue:
            '639333556684-6aqi4fughbj3p264q2lr8325c5j6uug4.apps.googleusercontent.com',
      ),
    ));
