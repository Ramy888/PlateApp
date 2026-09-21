import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:platepatch/data/auth_service.dart';
import 'package:platepatch/data/attestation.dart';
import 'package:platepatch/data/catalog.dart';
import 'package:platepatch/data/patch_images.dart';
import 'package:platepatch/data/prefs_repository.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:platepatch/data/scan_api.dart';
import 'package:platepatch/domain/models.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/state/auth_providers.dart';
import 'package:platepatch/state/scan_providers.dart';
import 'package:platepatch/ui/scan_result_screen.dart';
import 'package:platepatch/ui/widgets/ai_image.dart';
import 'package:platepatch/ui/theme.dart';
import 'package:platepatch/ui/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Catalog realCatalog() {
  List<T> parse<T>(String name, T Function(Map<String, dynamic>) fromJson) =>
      (jsonDecode(File('assets/data/$name.json').readAsStringSync()) as List<dynamic>)
          .map((j) => fromJson(j as Map<String, dynamic>))
          .toList();
  return Catalog(
    foods: parse('foods', FoodItem.fromJson),
    additions: parse('additions', Addition.fromJson),
  );
}

Uint8List realPhoto() => File('test/fixtures/meal_rice_chicken.jpg').readAsBytesSync();

/// Stands in for the Worker. Nothing here touches the network, so no test can
/// ever spend a scan or a cent.
class FakeScanApi implements ScanApi {
  FakeScanApi({
    this.response,
    this.failure,
    this.forgetThrows = false,
    this.previewFailure,
  });

  ScanResponse? response;
  ScanFailure? failure;
  final bool forgetThrows;
  final ScanFailure? previewFailure;

  /// What a chat turn will answer with, and what it was asked.
  ChatReply? chatReply;
  ScanFailure? chatFailure;
  final chatMessages = <String>[];
  final voiceClips = <int>[];
  final plateCalls = <(List<String>, String)>[];
  final signInTokens = <String>[];
  int signOuts = 0;
  ScanFailure? signInFailure;
  ScanFailure? plateFailure;
  String? plateImageUrl;
  final ratings = <(String, bool)>[];

  int registrations = 0;
  int scans = 0;
  int forgotten = 0;
  int challenges = 0;
  String? lastIntegrityToken;
  String? lastRcUserId;
  final reports = <Map<String, String?>>[];

  @override
  String get baseUrl => 'fake';

  @override
  Duration get timeout => const Duration(seconds: 1);

  ScanQuota quotaValue = ScanQuota(
    scans: 4,
    previews: 2,
    resetsAt: DateTime.fromMillisecondsSinceEpoch(1789310995000),
    pro: false,
    trialActive: true,
    trialDaysLeft: 7,
  );

  /// What the last AI call was told about the person, so a test can assert
  /// the model was not offered something they had ruled out.
  Set<String> lastAvoid = const {};
  String? lastGoal;

  @override
  Future<ChatReply> chat({
    required String deviceToken,
    required String message,
    Set<String> avoid = const {},
    String? goal,
  }) async {
    chatMessages.add(message);
    lastAvoid = avoid;
    lastGoal = goal;
    if (chatFailure != null) throw chatFailure!;
    return chatReply ??
        ChatReply(
          messageId: 'msg_fake',
          reply: 'Rice and chicken.',
          foodIds: const ['white_rice', 'chicken'],
          additionId: 'side_salad',
          imageUrl: null,
          disclaimer: 'AI visual preview — appearance and serving size are illustrative.',
          quota: quotaValue,
        );
  }

  @override
  Future<ChatReply> voice({
    required String deviceToken,
    required Uint8List audio,
    required String mimeType,
    Set<String> avoid = const {},
    String? goal,
  }) async {
    lastAvoid = avoid;
    lastGoal = goal;
    voiceClips.add(audio.length);
    if (chatFailure != null) throw chatFailure!;
    return chatReply ??
        ChatReply(
          messageId: 'msg_voice',
          reply: 'Rice and chicken.',
          foodIds: const ['white_rice', 'chicken'],
          additionId: 'side_salad',
          transcript: 'I had rice and chicken',
          imageUrl: null,
          disclaimer: 'AI visual preview — appearance and serving size are illustrative.',
          quota: quotaValue,
        );
  }

  @override
  Future<SignedInUser> signInWithGoogle({
    required String deviceToken,
    required String idToken,
  }) async {
    signInTokens.add(idToken);
    if (signInFailure != null) throw signInFailure!;
    return const SignedInUser(id: 'g1', email: 'someone@example.com', name: 'Someone');
  }

  @override
  Future<void> signOutOfServer(String deviceToken) async => signOuts++;

  @override
  Future<ChatReply> plate({
    required String deviceToken,
    required List<String> foodIds,
    required String additionId,
  }) async {
    plateCalls.add((foodIds, additionId));
    if (plateFailure != null) throw plateFailure!;
    return ChatReply(
      messageId: 'msg_plate',
      reply: 'A good plate, rounded out.',
      foodIds: foodIds,
      additionId: additionId,
      imageUrl: plateImageUrl,
      disclaimer: 'AI visual preview — appearance and serving size are illustrative.',
      quota: quotaValue,
    );
  }

  @override
  Future<void> rate({
    required String deviceToken,
    required String messageId,
    required bool helpful,
  }) async {
    ratings.add((messageId, helpful));
  }

  @override
  Future<String> challenge() async {
    challenges++;
    return 'nonce_fake';
  }

  @override
  Future<DeviceRegistration> registerDevice({
    required String platform,
    String? integrityToken,
    String? rcUserId,
  }) async {
    registrations++;
    lastIntegrityToken = integrityToken;
    lastRcUserId = rcUserId;
    return DeviceRegistration(token: 'dv_fake', quota: quotaValue);
  }

  @override
  Future<ScanQuota> quota(String deviceToken) async => quotaValue;

  /// Names the app asked the server to describe, and what it answered.
  final describeCalls = <List<String>>[];
  List<FoodItem> describedFoods = const [];

  @override
  Future<List<FoodItem>> describe({
    required String deviceToken,
    required List<String> names,
  }) async {
    describeCalls.add(names);
    return describedFoods;
  }

  /// Every forced entitlement re-check, with the RevenueCat id it carried.
  /// A purchase that never reaches the server is a customer who paid for
  /// nothing, so the tests assert on this list rather than on a flag.
  final entitlementRefreshes = <String?>[];

  /// What the server says once it has re-checked. Defaults to the unchanged
  /// allowance, so a test has to opt in to the upgrade.
  ScanQuota? refreshedQuota;

  @override
  Future<ScanQuota> refreshEntitlement(String deviceToken, {String? rcUserId}) async {
    entitlementRefreshes.add(rcUserId);
    return quotaValue = refreshedQuota ?? quotaValue;
  }

  @override
  Future<ScanResponse> scan({required String deviceToken, required Uint8List jpeg}) async {
    scans++;
    final f = failure;
    if (f != null) throw f;
    return response!;
  }

  @override
  Future<void> report({
    required String deviceToken,
    required String targetType,
    required String targetId,
    required String reason,
    String? note,
  }) async {
    reports.add({'reason': reason, 'note': note, 'targetId': targetId});
  }

  PreviewResult? previewResult;
  int previews = 0;
  String? lastAdditionId;

  @override
  Future<PreviewResult> preview({
    required String deviceToken,
    required Uint8List jpeg,
    required String additionId,
    String? scanId,
  }) async {
    previews++;
    lastAdditionId = additionId;
    previewCalls.add(additionId);
    final f = previewFailureNow ?? previewFailure;
    if (f != null) throw f;
    return previewResult ??
        PreviewResult(
          url: 'https://fake/v1/preview/abc.jpg',
          disclaimer: 'AI visual preview — appearance and serving size are illustrative.',
          quota: quotaValue,
        );
  }

  @override
  Future<Uint8List> previewImage({
    required String deviceToken,
    required String url,
  }) async =>
      previewBytes ?? Uint8List.fromList(List.filled(2048, 7));

  /// Set where a test needs bytes a decoder will actually accept.
  Uint8List? previewBytes;

  /// Every addition the app actually paid to have drawn, in order. A count
  /// would hide the thing worth asserting: which ones, and whether one was
  /// bought twice.
  final previewCalls = <String>[];

  /// A failure switched on partway through a test, unlike the constructor one.
  ScanFailure? previewFailureNow;

  @override
  Future<void> forgetDevice(String deviceToken) async {
    if (forgetThrows) {
      throw const ScanFailure(ScanError.offline, 'No connection.');
    }
    forgotten++;
  }

  @override
  void close() {}
}

/// A plate of something the catalogue has never heard of.
ScanResponse pancakes() => ScanResponse.fromJson({
      'scanId': 'sc_pan',
      'foods': [
        {'name': 'pancakes', 'confidence': 0.96},
      ],
      'components': {
        'protein': 'uncertain',
        'fibre': 'uncertain',
        'healthyFat': 'uncertain',
      },
      'quota': {
        'scans': 300,
        'previews': 12,
        'resetsAt': 1789310995,
        'pro': true,
        'trialActive': false,
        'trialDaysLeft': 0,
      },
    });

ScanResponse riceAndChicken() => ScanResponse.fromJson({
      'scanId': 'sc_test',
      'foods': [
        {'name': 'white rice', 'confidence': 0.98},
        {'name': 'roast chicken thigh', 'confidence': 0.95},
      ],
      'components': {
        'protein': 'present',
        'fibre': 'possibly_missing',
        'healthyFat': 'possibly_missing',
      },
      'quota': {
        'scans': 4,
        'previews': 2,
        'resetsAt': 1789310995,
        'pro': false,
        'trialActive': true,
        'trialDaysLeft': 7,
      },
    });

Future<ProviderContainer> pump(
  WidgetTester tester, {
  required FakeScanApi api,
  Map<String, Object> prefs = const {'onboarded': true},
  Widget? home,
  Attestation attestation = const NoAttestation(token: 'integrity_fake'),
  PurchasesService? purchases,
  bool signedIn = false,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final repo = PrefsRepository(await SharedPreferences.getInstance());
  final container = ProviderContainer(overrides: [
    prefsRepositoryProvider.overrideWithValue(repo),
    patchImagesProvider.overrideWithValue(MemoryPatchImages()),
    catalogProvider.overrideWithValue(realCatalog()),
    purchasesServiceProvider.overrideWithValue(purchases ?? InertPurchasesService()),
    authServiceProvider.overrideWithValue(signedIn ? SignedInAuth() : InertAuthService()),
    scanApiProvider.overrideWithValue(api),
    attestationProvider.overrideWithValue(attestation),
  ]);
  addTearDown(container.dispose);

  if (signedIn) await container.read(authControllerProvider.notifier).signIn();

  if (home != null) {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }
  return container;
}

/// Signed in, without going near Google. The paid paths refuse a guest, so a
/// test about what happens *after* the refusal needs an account.
class SignedInAuth implements AuthService {
  @override
  Future<GoogleCredential?> signIn() async =>
      const GoogleCredential(idToken: 'tok', email: 'a@b.c', name: 'Tester');

  @override
  Future<GoogleCredential?> restore() async => null;

  @override
  Future<void> signOut() async {}
}

/// A store that actually completes a purchase, which [InertPurchasesService]
/// deliberately does not. Needed to test what happens *after* one succeeds.
class FakePurchases implements PurchasesService {
  FakePurchases({this.userId, this.succeeds = true, this.startsPro = false});


  final String? userId;
  final bool succeeds;

  /// A subscription that already existed when the app was opened.
  /// Mutable, so a test can let a purchase happen outside the app the way a
  /// Play Store redemption does.
  bool startsPro;

  @override
  Future<ProStatus> init() async => ProStatus(isPro: startsPro, configured: true);

  @override
  Future<ProStatus> purchase(Package package) async =>
      ProStatus(isPro: succeeds, configured: true);

  @override
  Future<ProStatus> restore() async => ProStatus(isPro: succeeds, configured: true);

  @override
  Future<ProStatus> sync() async => ProStatus(isPro: startsPro, configured: true);

  @override
  Future<String?> appUserId() async => userId;
}

/// The cheapest thing that satisfies `buy`. Nothing reads it — the fake store
/// above ignores it — but the signature needs one.
Package fakePackage() => Package.fromJson(const {
      'identifier': r'$rc_monthly',
      'packageType': 'MONTHLY',
      'product': {
        'identifier': 'platepatch_pro_monthly',
        'description': 'Plate Pro, monthly',
        'title': 'Plate Pro',
        'price': 4.99,
        'priceString': r'$4.99',
        'currencyCode': 'USD',
        'productCategory': 'SUBSCRIPTION',
      },
      'presentedOfferingContext': {
        'offeringIdentifier': 'default',
        'placementIdentifier': null,
        'targetingContext': null,
      },
    });

void main() {
  group('a successful scan', () {
    testWidgets('matches the model output onto catalogue foods', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api);

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      final state = container.read(scanControllerProvider);
      expect(state.stage, ScanStage.done);
      expect(state.recognized.map((f) => f.food?.id), ['white_rice', 'chicken']);
      expect(state.quota?.scans, 4);
    });

    testWidgets('registers the device once, then reuses the token', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api);
      final controller = container.read(scanControllerProvider.notifier);

      await controller.scan(realPhoto(), slot: MealSlot.lunchDinner);
      await controller.scan(realPhoto(), slot: MealSlot.lunchDinner);

      expect(api.registrations, 1);
      expect(api.scans, 2);
      expect(container.read(prefsRepositoryProvider).deviceToken, 'dv_fake');
    });

    testWidgets('never registers for someone who only builds by hand', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      await pump(tester, api: api);
      // No scan attempted: the app has made no network call at all.
      expect(api.registrations, 0);
    });

    testWidgets('confirming hands the foods to the existing meal draft', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api);
      final controller = container.read(scanControllerProvider.notifier);

      await controller.scan(realPhoto(), slot: MealSlot.lunchDinner);
      controller.confirm(MealSlot.lunchDinner);

      final draft = container.read(mealDraftProvider);
      expect(draft.slot, MealSlot.lunchDinner);
      expect(draft.foodIds, {'white_rice', 'chicken'});

      // And the rule engine now produces a patch from it, exactly as it would
      // for a hand-built meal.
      final result = container.read(patchResultProvider);
      expect(result.gaps, contains(Nutrient.fibre));
      expect(result.patches, isNotEmpty);
    });
  });

  group('attestation', () {
    testWidgets('binds an integrity token to a server-issued nonce', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api);

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      expect(api.challenges, 1, reason: 'no nonce was requested');
      expect(api.lastIntegrityToken, 'integrity_fake');
    });

    testWidgets('registers anyway when no token can be obtained', (tester) async {
      // Emulators, sideloaded builds and phones without Play Services all end
      // up here. The server decides whether to allow it, not the client.
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        attestation: const NoAttestation(),
      );

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      expect(api.registrations, 1);
      expect(api.lastIntegrityToken, isNull);
      expect(container.read(scanControllerProvider).stage, ScanStage.done);
    });

    testWidgets('a rejected installation says so without blaming the phone',
        (tester) async {
      final api = FakeScanApi(
        failure: const ScanFailure(
          ScanError.attestationFailed,
          'This app installation could not be verified.',
        ),
      );
      final container = await pump(tester, api: api);

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      expect(container.read(scanControllerProvider).failure?.error,
          ScanError.attestationFailed);
    });

    testWidgets('only one nonce is fetched across repeated scans', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api);
      final controller = container.read(scanControllerProvider.notifier);

      await controller.scan(realPhoto(), slot: MealSlot.lunchDinner);
      await controller.scan(realPhoto(), slot: MealSlot.lunchDinner);

      // Registration happens once, so attestation happens once.
      expect(api.challenges, 1);
    });
  });

  group('when the photo is not good enough', () {
    testWidgets('a blurry photo is refused without any request', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api);

      // A tiny image trips the size gate; nothing reaches the network.
      await container
          .read(scanControllerProvider.notifier)
          .scan(Uint8List.fromList([1, 2, 3]), slot: MealSlot.snack);

      final state = container.read(scanControllerProvider);
      expect(state.stage, ScanStage.failed);
      // `problem`, not `failure`: a photo refused on this phone sets a
      // rejection and no failure. The camera screen read `failure` and so said
      // nothing at all — the spinner stopped and the shutter could be pressed
      // forever. Anything showing an error here must read `problem`.
      expect(state.failure, isNull);
      expect(state.problem, isNotNull);
      expect(api.scans, 0, reason: 'a rejected photo must not cost a scan');
      expect(api.registrations, 0);
    });
  });

  group('when the server says no', () {
    testWidgets('an exhausted quota is reported as an upgrade prompt', (tester) async {
      final api = FakeScanApi(
        failure: const ScanFailure(ScanError.quotaExhausted, 'You have used this week’s scans.'),
      );
      final container = await pump(tester, api: api);

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      final state = container.read(scanControllerProvider);
      expect(state.failure?.error.suggestsUpgrade, isTrue);
      expect(state.problem, contains('scans'));
    });

    testWidgets('every failure message offers the manual builder', (tester) async {
      for (final failure in [
        const ScanFailure(ScanError.busy, 'Recognition is busy. Try again, or build by hand.'),
        const ScanFailure(ScanError.noFoodFound, 'No food recognised. Or build the meal by hand.'),
        const ScanFailure(ScanError.offline, 'No connection. You can build the meal by hand.'),
      ]) {
        final api = FakeScanApi(failure: failure);
        final container = await pump(tester, api: api);
        await container
            .read(scanControllerProvider.notifier)
            .scan(realPhoto(), slot: MealSlot.lunchDinner);
        expect(
          container.read(scanControllerProvider).problem!.toLowerCase(),
          contains('hand'),
          reason: '${failure.error} leaves the user with nowhere to go',
        );
      }
    });

    testWidgets('a stale token is cleared so the next scan re-registers', (tester) async {
      final api = FakeScanApi(
        failure: const ScanFailure(ScanError.unauthorized, 'Sign in again.'),
      );
      final container = await pump(
        tester,
        api: api,
        prefs: {'onboarded': true, 'device_token': 'dv_stale'},
      );

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      expect(container.read(prefsRepositoryProvider).deviceToken, isNull);
    });
  });

  group('the scan result screen', () {
    Future<ProviderContainer> withResult(WidgetTester tester, ScanResponse response) async {
      final api = FakeScanApi(response: response);
      final container = await pump(tester, api: api);
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(),
            home: const ScanResultScreen(slot: MealSlot.lunchDinner),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows what the model saw', (tester) async {
      await withResult(tester, riceAndChicken());
      expect(find.text('Rice'), findsWidgets);
      expect(find.text('Chicken'), findsWidgets);
    });

    testWidgets('a wrong item can be removed in one tap', (tester) async {
      final container = await withResult(tester, riceAndChicken());
      await tester.tap(find.byTooltip('Remove Chicken'));
      await tester.pumpAndSettle();

      expect(container.read(scanControllerProvider).recognized.map((f) => f.food?.id),
          ['white_rice']);
    });

    testWidgets('an unmatched label is shown and marked as not counting', (tester) async {
      await withResult(
        tester,
        ScanResponse.fromJson({
          'scanId': 'sc_x',
          'foods': [
            {'name': 'white rice', 'confidence': 0.9},
            {'name': 'pickled turnip', 'confidence': 0.5},
          ],
          'components': {'protein': 'uncertain', 'fibre': 'uncertain', 'healthyFat': 'uncertain'},
          'quota': {
            'scans': 3,
            'previews': 2,
            'resetsAt': 1789310995,
            'pro': false,
            'trialActive': true,
            'trialDaysLeft': 7,
          },
        }),
      );
      expect(find.text('Pickled turnip'), findsOneWidget);
      expect(find.textContaining('will not count'), findsOneWidget);
    });

    testWidgets('says the result came from AI, and what happened to the photo',
        (tester) async {
      // Play expects this disclosure where the generated result is shown.
      await withResult(tester, riceAndChicken());
      expect(find.textContaining('Recognised by AI'), findsOneWidget);
      expect(find.textContaining('stripped of location data'), findsOneWidget);
    });

    testWidgets('offers the Play-required report control', (tester) async {
      await withResult(tester, riceAndChicken());
      expect(find.byTooltip('Report this result'), findsOneWidget);
    });

    testWidgets('a missed food can be added from the same catalogue', (tester) async {
      final container = await withResult(tester, riceAndChicken());
      // Folded away by default: the common case is that the reading was right.
      await tester.tap(find.text('Did it miss something?'));
      await tester.pumpAndSettle();
      final salad = find.widgetWithText(PlateChip, 'Salad');
      await tester.ensureVisible(salad);
      await tester.pumpAndSettle();
      await tester.tap(salad);
      await tester.pumpAndSettle();

      expect(
        container.read(scanControllerProvider).recognized.map((f) => f.food?.id),
        contains('salad'),
      );
    });

    testWidgets('a food the catalogue does not know is described, and answered',
        (tester) async {
      // Photographed pancakes. The catalogue has fifty-one foods and no
      // pancakes, and the journey used to end there. The engine never needed
      // the name — only the protein, fibre and fat.
      final api = FakeScanApi(response: pancakes())
        ..describedFoods = [
          const FoodItem(
            id: 'described:pancakes',
            name: 'Pancakes',
            emoji: '',
            icon: 'utensils',
            group: 'grains',
            slots: {MealSlot.breakfast, MealSlot.lunchDinner, MealSlot.snack},
            provides: NutrientScores(protein: 1, fibre: 0, fat: 1),
            tags: {'carb', 'gluten'},
          ),
        ];
      final container = await pump(tester, api: api, signedIn: true);
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(),
            home: const ScanResultScreen(slot: MealSlot.lunchDinner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.describeCalls, [['pancakes']]);
      // And now there is a real answer where there used to be a shrug.
      final result = container.read(patchResultProvider);
      expect(result.foods.map((f) => f.id), ['described:pancakes']);
      expect(result.patches, isNotEmpty);
    });

    testWidgets('a food the catalogue does not know draws nothing', (tester) async {
      // Photographed pancakes. The model read them correctly, the catalogue
      // has no such food, so the engine sees an empty plate — and the page
      // went on to generate a picture from nothing, which came back as mash
      // and carrots labelled as the user's own meal, having spent an AI meal
      // to do it.
      final api = FakeScanApi(
        response: ScanResponse.fromJson({
          'scanId': 'sc_pan',
          'foods': [
            {'name': 'pancakes', 'confidence': 0.96},
          ],
          'components': {
            'protein': 'uncertain',
            'fibre': 'uncertain',
            'healthyFat': 'uncertain',
          },
          'quota': {
            'scans': 300,
            'previews': 12,
            'resetsAt': 1789310995,
            'pro': true,
            'trialActive': false,
            'trialDaysLeft': 0,
          },
        }),
      );
      final container = await pump(tester, api: api, signedIn: true);
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(),
            home: const ScanResultScreen(slot: MealSlot.lunchDinner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.plateCalls, isEmpty,
          reason: 'nothing recognised is nothing to draw, and nothing to pay for');
      // And the tab that switches to a picture that does not exist is gone.
      expect(find.text('With the addition'), findsNothing);

      // The explanation sits below the fold of a lazy list.
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('nothing to suggest'), findsOneWidget);
      expect(find.text('Add what you are eating'), findsNothing);
    });

    testWidgets('an emptied plate asks for food rather than congratulating it',
        (tester) async {
      // There is no confirm step to block any more. What matters is that the
      // page does not tell someone with an empty plate that it "covers the
      // basics", which is what the balanced message would have said.
      final container = await withResult(tester, riceAndChicken());
      final controller = container.read(scanControllerProvider.notifier);
      for (final food in [...container.read(scanControllerProvider).recognized]) {
        controller.remove(food);
      }
      await tester.pumpAndSettle();

      expect(find.text('Add what you are eating'), findsOneWidget);
      expect(find.textContaining('covers the basics'), findsNothing);
      expect(find.text('Save to my plates'), findsNothing);
    });

    testWidgets('removing a food changes the suggestion on the spot',
        (tester) async {
      // The confirm step used to be the thing that handed the meal to the
      // engine. On one page the engine has to follow every tap.
      final container = await withResult(tester, riceAndChicken());
      final before = container.read(patchResultProvider).patches.first.addition.id;

      final chicken = container
          .read(scanControllerProvider)
          .recognized
          .firstWhere((f) => f.food?.id == 'chicken');
      container.read(scanControllerProvider.notifier).remove(chicken);
      await tester.pumpAndSettle();

      // The draft is what the engine watches. If this does not follow the
      // chips, the suggestion on screen belongs to a meal the user has edited
      // away — which is exactly what the removed confirm step used to prevent.
      expect(container.read(mealDraftProvider).foodIds, {'white_rice'});
      expect(container.read(patchResultProvider).foods.map((f) => f.id), ['white_rice']);
      // `before` is read only to prove the engine actually ran again.
      expect(before, isNotEmpty);
    });

    testWidgets('says why a picture could not be drawn', (tester) async {
      // Free tries are shared with scanning, so the first suggestion draws and
      // the next is refused. Rendering nothing makes the page look broken
      // rather than spent — the same silent failure scanning had.
      // Allowance is shared with scanning, so the picture is the first thing
      // to be refused. Rendering nothing makes the page look broken rather
      // than spent — the silent failure scanning used to have.
      final api = FakeScanApi(response: riceAndChicken())
        ..plateFailure = const ScanFailure(
          ScanError.trialEnded,
          'You have used your three free AI meals.',
        );
      final container = await pump(tester, api: api, signedIn: true);
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(),
            home: const ScanResultScreen(slot: MealSlot.lunchDinner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Subscribe to keep drawing'), findsOneWidget);
    });

    testWidgets('two tabs choose between the drawn plate and the photograph',
        (tester) async {
      // Two pictures answering different questions: the drawn plate is the
      // suggestion, the photograph is how someone checks the app read their
      // meal correctly. Tabs rather than a toggle, so both are visible as
      // choices at rest.
      final api = FakeScanApi(response: riceAndChicken())
        ..previewBytes = realPhoto()
        ..plateImageUrl = 'https://example.test/plate.png';
      final container = await pump(tester, api: api, signedIn: true);
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(),
            home: const ScanResultScreen(slot: MealSlot.lunchDinner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('With the addition'), findsOneWidget);
      expect(find.text('Your photo'), findsOneWidget);

      // The drawn plate leads, carrying its AI label.
      expect(find.byType(AiImage), findsOneWidget);

      // The photograph is one tap away — and is not labelled AI, because it
      // is the user's own picture.
      await tester.tap(find.text('Your photo'));
      await tester.pumpAndSettle();
      expect(find.byType(AiImage), findsNothing);

      await tester.tap(find.text('With the addition'));
      await tester.pumpAndSettle();
      expect(find.byType(AiImage), findsOneWidget);
    });

    testWidgets('the picture is drawn without being asked', (tester) async {
      // The button that used to stand between the suggestion and its picture
      // made the answer look like a preview of a preview.
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api, signedIn: true);
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(),
            home: const ScanResultScreen(slot: MealSlot.lunchDinner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('See it on my photo'), findsNothing);
      expect(api.plateCalls, isNotEmpty,
          reason: 'the plate should be drawn on arrival, not on request');
    });
  });

  group('delete my data', () {
    testWidgets('clears the phone and tells the server to forget the device',
        (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        prefs: {
          'onboarded': true,
          'device_token': 'dv_fake',
          'diet_prefs': <String>['vegetarian'],
        },
      );
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);
      container.read(scanControllerProvider.notifier).confirm(MealSlot.lunchDinner);
      await container.read(historyProvider.notifier).save(SavedPatch(
            id: 'p1',
            savedAt: DateTime(2026, 9, 6),
            slot: MealSlot.lunchDinner,
            foodIds: const ['white_rice'],
            additionId: 'yogurt',
            additionName: 'Add a small bowl of yogurt',
            additionEmoji: '🥣',
            gapIds: const ['protein'],
          ));

      await container.read(scanControllerProvider.notifier).deleteEverything();

      final repo = container.read(prefsRepositoryProvider);
      expect(api.forgotten, 1, reason: 'the server was not told to forget the device');
      expect(repo.deviceToken, isNull);
      expect(repo.history, isEmpty);
      expect(repo.dietPrefs, isEmpty);
      expect(container.read(historyProvider), isEmpty);
      expect(container.read(mealDraftProvider).isEmpty, isTrue);
      expect(container.read(scanControllerProvider).recognized, isEmpty);
    });

    testWidgets('still clears the phone when the server cannot be reached',
        (tester) async {
      // Someone asking to be forgotten must not leave with nothing deleted
      // because the network was down.
      final api = FakeScanApi(response: riceAndChicken(), forgetThrows: true);
      final container = await pump(
        tester,
        api: api,
        prefs: {'onboarded': true, 'device_token': 'dv_fake', 'diet_prefs': <String>['low_cost']},
      );

      await container.read(scanControllerProvider.notifier).deleteEverything();

      final repo = container.read(prefsRepositoryProvider);
      expect(repo.deviceToken, isNull);
      expect(repo.dietPrefs, isEmpty);
    });
  });

  group('the seven-day trial', () {
    testWidgets('the app is told how much of the week is left', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(tester, api: api);

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      final quota = container.read(scanControllerProvider).quota!;
      expect(quota.trialActive, isTrue);
      expect(quota.trialDaysLeft, 7);
    });

    testWidgets('a finished trial is an upgrade prompt, not an error',
        (tester) async {
      final api = FakeScanApi(
        failure: const ScanFailure(
          ScanError.trialEnded,
          'Your free week of meal scans has ended. Subscribe to keep scanning — '
          'building meals by hand is still free.',
        ),
      );
      final container = await pump(tester, api: api);

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      final failure = container.read(scanControllerProvider).failure!;
      expect(failure.error.isTrialEnded, isTrue);
      expect(failure.error.suggestsUpgrade, isTrue);
      // And it still says the free part of the app is unaffected.
      expect(failure.message, contains('by hand is still free'));
    });

    testWidgets('the manual builder keeps working after the trial ends',
        (tester) async {
      // The whole point of the pricing: losing the camera must not lose the app.
      final api = FakeScanApi(
        failure: const ScanFailure(ScanError.trialEnded, 'Your free week has ended.'),
      );
      final container = await pump(tester, api: api);
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      container.read(mealDraftProvider.notifier).toggleFood('white_rice');
      container.read(mealDraftProvider.notifier).toggleFood('chicken');

      final result = container.read(patchResultProvider);
      expect(result.patches, isNotEmpty);
      expect(api.scans, 1, reason: 'building by hand must not call the API');
    });

    testWidgets('the RevenueCat id is sent so the server can verify it',
        (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        purchases: InertPurchasesService(userId: 'rc_user_123'),
      );

      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);

      expect(api.lastRcUserId, 'rc_user_123');
    });

    testWidgets('a purchase refreshes the allowance from the server',
        (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );
      api.quotaValue = ScanQuota(
        scans: 30,
        previews: 10,
        resetsAt: DateTime.fromMillisecondsSinceEpoch(1789310995000),
        pro: true,
      );

      await container.read(scanControllerProvider.notifier).onEntitlementChanged();

      final quota = container.read(scanControllerProvider).quota!;
      expect(quota.pro, isTrue);
      expect(quota.scans, 30);
    });

    testWidgets('buying tells the server, with the RevenueCat id',
        (tester) async {
      // The bug this is here for: onEntitlementChanged existed, was tested
      // directly, and nothing ever called it. A customer paid, Google mailed a
      // receipt, and the voice button still sent them to the paywall — because
      // the only thing that had changed was the phone's own opinion. The
      // server verifies with RevenueCat and had not been asked to look again.
      final api = FakeScanApi(response: riceAndChicken());
      final purchases = FakePurchases(userId: 'rcu_buyer');
      final container = await pump(
        tester,
        api: api,
        purchases: purchases,
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );
      api.refreshedQuota = ScanQuota(
        scans: 30,
        previews: 10,
        resetsAt: DateTime.fromMillisecondsSinceEpoch(1789310995000),
        pro: true,
      );

      await container.read(proProvider.notifier).buy(fakePackage());

      expect(api.entitlementRefreshes, ['rcu_buyer'],
          reason: 'a purchase the server never hears about is a wall');
      expect(container.read(scanControllerProvider).quota!.pro, isTrue);
    });

    testWidgets('restoring tells the server too', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        purchases: FakePurchases(userId: 'rcu_restorer'),
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );

      await container.read(proProvider.notifier).restore();

      expect(api.entitlementRefreshes, ['rcu_restorer']);
    });

    testWidgets('a code redeemed outside the app is picked up', (tester) async {
      // The judge path: redeem in the Play Store, come back. The SDK does not
      // hear about it on its own, so the app went on showing a paywall to
      // someone who had already paid — recoverable only through Restore
      // purchases, which nobody hunting for it has a reason to find.
      final api = FakeScanApi(response: riceAndChicken());
      final purchases = FakePurchases(userId: 'rcu_redeemer');
      final container = await pump(
        tester,
        api: api,
        purchases: purchases,
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );
      await container.read(proProvider.notifier).init();
      expect(container.read(proProvider).isPro, isFalse);

      // The redemption happens elsewhere; the store knows, the app does not.
      purchases.startsPro = true;
      api.refreshedQuota = ScanQuota(
        scans: 300,
        previews: 12,
        resetsAt: DateTime.fromMillisecondsSinceEpoch(1789310995000),
        pro: true,
      );

      await container.read(proProvider.notifier).sync();

      expect(container.read(proProvider).isPro, isTrue);
      expect(api.entitlementRefreshes, ['rcu_redeemer'],
          reason: 'the server has to be told, or the paywall stands');
    });

    testWidgets('resuming repeatedly does not hammer the store', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final purchases = FakePurchases(userId: 'rcu_switcher', startsPro: true);
      final container = await pump(
        tester,
        api: api,
        purchases: purchases,
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );
      final pro = container.read(proProvider.notifier);

      await pro.sync();
      await pro.sync();
      await pro.sync();

      expect(api.entitlementRefreshes, hasLength(1),
          reason: 'app switching must not cost a round trip each time');
    });

    testWidgets('an existing subscriber is repaired on launch', (tester) async {
      // The customer who paid on the broken build is the one who can never fix
      // themselves: they will not tap buy again, and they have no reason to
      // tap restore. Launching has to be enough.
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        purchases: FakePurchases(userId: 'rcu_already_paid', startsPro: true),
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );
      api.refreshedQuota = ScanQuota(
        scans: 30,
        previews: 10,
        resetsAt: DateTime.fromMillisecondsSinceEpoch(1789310995000),
        pro: true,
      );

      await container.read(proProvider.notifier).init();

      expect(api.entitlementRefreshes, ['rcu_already_paid']);
      expect(container.read(scanControllerProvider).quota!.pro, isTrue);
    });

    testWidgets('launching without a subscription stays quiet', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        purchases: FakePurchases(userId: 'rcu_free'),
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );

      await container.read(proProvider.notifier).init();

      expect(api.entitlementRefreshes, isEmpty,
          reason: 'every free launch must not cost a RevenueCat call');
    });

    testWidgets('a purchase that did not go through says nothing to the server',
        (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        purchases: FakePurchases(userId: 'rcu_cancelled', succeeds: false),
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );

      await container.read(proProvider.notifier).buy(fakePackage());

      expect(api.entitlementRefreshes, isEmpty,
          reason: 'a cancelled purchase is not a reason to call RevenueCat');
    });
  });

  group('reporting', () {
    testWidgets('sends the reason and the scan it refers to', (tester) async {
      final api = FakeScanApi(response: riceAndChicken());
      final container = await pump(
        tester,
        api: api,
        prefs: {'onboarded': true, 'device_token': 'dv_fake'},
      );
      await container
          .read(scanControllerProvider.notifier)
          .scan(realPhoto(), slot: MealSlot.lunchDinner);
      await container
          .read(scanControllerProvider.notifier)
          .report(reason: 'wrong_food', note: 'that is not chicken');

      expect(api.reports.single['reason'], 'wrong_food');
      expect(api.reports.single['targetId'], 'sc_test');
    });
  });
}
