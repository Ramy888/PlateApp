import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platepatch/data/auth_service.dart';
import 'package:platepatch/data/catalog.dart';
import 'package:platepatch/data/patch_images.dart';
import 'package:platepatch/data/prefs_repository.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:platepatch/data/scan_api.dart';
import 'package:platepatch/domain/models.dart';
import 'package:platepatch/state/auth_providers.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/state/scan_providers.dart';
import 'package:platepatch/ui/meal_screen.dart';
import 'package:platepatch/ui/settings_screen.dart';
import 'package:platepatch/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scan_flow_test.dart' show FakeScanApi;

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

/// A Google account that is whatever the test needs it to be.
class FakeAuthService implements AuthService {
  FakeAuthService({this.credential, this.restorable});

  /// What `signIn()` returns. Null means the person cancelled.
  GoogleCredential? credential;

  /// What a silent restore finds, if anything.
  GoogleCredential? restorable;

  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<GoogleCredential?> signIn() async {
    signInCalls++;
    return credential;
  }

  @override
  Future<GoogleCredential?> restore() async => restorable;

  @override
  Future<void> signOut() async => signOutCalls++;
}

const _google = GoogleCredential(
  idToken: 'id-token-abc',
  email: 'someone@example.com',
  name: 'Someone Else',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeScanApi api,
  required FakeAuthService auth,
  Widget home = const MealScreen(),
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'onboarded': true, 'device_token': 'dv_fake'});
  final repo = PrefsRepository(await SharedPreferences.getInstance());
  final container = ProviderContainer(
    overrides: [
      prefsRepositoryProvider.overrideWithValue(repo),
      patchImagesProvider.overrideWithValue(MemoryPatchImages()),
      catalogProvider.overrideWithValue(_realCatalog()),
      purchasesServiceProvider.overrideWithValue(InertPurchasesService()),
      scanApiProvider.overrideWithValue(api),
      authServiceProvider.overrideWithValue(auth),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(theme: buildTheme(), home: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a guest sees the whole hub, unasked', (tester) async {
    await _pump(tester, api: FakeScanApi(), auth: FakeAuthService());

    expect(find.text('What are you eating?'), findsOneWidget);
    expect(find.text('Lunch or dinner'), findsOneWidget);
    // Nothing has interrupted them.
    expect(find.textContaining('Sign in to use the AI'), findsNothing);
  });

  testWidgets('reaching for the chat asks a guest to sign in', (tester) async {
    final auth = FakeAuthService();
    await _pump(tester, api: FakeScanApi(), auth: auth);

    await tester.tap(find.text('Describe your meal…'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to use the AI'), findsOneWidget);
    expect(find.text('Describe your meal'), findsOneWidget);
  });

  testWidgets('"Not now" closes the sheet and opens nothing', (tester) async {
    final api = FakeScanApi();
    await _pump(tester, api: api, auth: FakeAuthService());

    await tester.tap(find.text('Describe your meal…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to use the AI'), findsNothing);
    // And crucially, nothing was sent to find that out.
    expect(api.chatMessages, isEmpty);
    expect(api.signInTokens, isEmpty);
  });

  testWidgets('signing in forwards the Google token and opens what was asked for',
      (tester) async {
    final api = FakeScanApi();
    final auth = FakeAuthService(credential: _google);
    final container = await _pump(tester, api: api, auth: auth);

    await tester.tap(find.text('Describe your meal…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(api.signInTokens, ['id-token-abc']);
    expect(container.read(authControllerProvider).isSignedIn, isTrue);
    expect(find.text('Describe your meal'), findsOneWidget);
  });

  testWidgets('cancelling the Google sheet says nothing at all', (tester) async {
    // credential stays null: the person backed out of Google's own dialog.
    final auth = FakeAuthService();
    final container = await _pump(tester, api: FakeScanApi(), auth: auth);

    await tester.tap(find.text('Describe your meal…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(container.read(authControllerProvider).isSignedIn, isFalse);
    expect(container.read(authControllerProvider).problem, isNull);
  });

  testWidgets('a failed sign-in is explained in the sheet', (tester) async {
    final api = FakeScanApi()
      ..signInFailure =
          const ScanFailure(ScanError.signInFailed, 'That sign-in could not be verified.');
    await _pump(tester, api: api, auth: FakeAuthService(credential: _google));

    await tester.tap(find.text('Describe your meal…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('That sign-in could not be verified.'), findsOneWidget);
  });

  testWidgets('a returning user is signed in without being asked', (tester) async {
    final auth = FakeAuthService(restorable: _google);
    final container = await _pump(tester, api: FakeScanApi(), auth: auth);
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).isSignedIn, isTrue);
    expect(auth.signInCalls, 0);
    expect(find.textContaining('Hello, Someone'), findsOneWidget);
  });

  testWidgets('settings shows the account, and signing out clears it',
      (tester) async {
    final api = FakeScanApi();
    final auth = FakeAuthService(restorable: _google);
    final container = await _pump(
      tester,
      api: api,
      auth: auth,
      home: const SettingsScreen(),
    );
    await container.read(authControllerProvider.notifier).restore();
    await tester.pumpAndSettle();

    expect(find.text('someone@example.com'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).isSignedIn, isFalse);
    expect(auth.signOutCalls, 1);
    expect(api.signOuts, 1);
  });

  // Play requires a way to delete the account from inside the app.
  testWidgets('deleting offers to remove the account, not just the device',
      (tester) async {
    await _pump(
      tester,
      api: FakeScanApi(),
      auth: FakeAuthService(),
      home: const SettingsScreen(),
    );

    await tester.scrollUntilVisible(find.text('Delete my account and data'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Delete my account and data'), findsOneWidget);
  });
}
