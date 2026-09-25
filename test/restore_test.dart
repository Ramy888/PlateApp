import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:platepatch/data/catalog.dart';
import 'package:platepatch/data/prefs_repository.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:platepatch/data/scan_api.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/state/scan_providers.dart';
import 'package:platepatch/ui/settings_screen.dart';
import 'package:platepatch/ui/theme.dart';

/// A server that is having a bad day in a way nobody anticipated.
///
/// Deliberately *not* a [ScanFailure]: the app's own error type is caught
/// everywhere it is thrown. What gets through is the exception nobody wrote a
/// `catch` for — a shape change in a response, a plugin throwing a
/// [PlatformException], a cast that fails. Those are the ones that escape a
/// background repair and take a user-facing message down with them.
class SulkingApi implements ScanApi {
  int refreshes = 0;

  @override
  Future<ScanQuota> refreshEntitlement(String deviceToken, {String? rcUserId}) async {
    refreshes++;
    throw StateError('unexpected response shape');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A store where the subscription is real and restoring it works.
class RestoringStore implements PurchasesService {
  int restores = 0;

  ProStatus get _pro => const ProStatus(
        isPro: true,
        configured: true,
        plan: ProPlan.yearly,
        inTrial: true,
      );

  @override
  Future<ProStatus> init() async => _pro;

  @override
  Future<ProStatus> restore() async {
    restores++;
    return _pro.copyWith(message: 'Pro restored.');
  }

  @override
  Future<ProStatus> purchase(Package package) async => _pro;

  @override
  Future<ProStatus> sync() async => _pro;

  @override
  Future<ProStatus> upgradeToYearly() async => _pro;

  @override
  Future<ProStatus> identify(String appUserId) async => _pro;

  @override
  Future<ProStatus> forget() async => const ProStatus(configured: true);

  @override
  Future<String?> appUserId() async => 'rcu_test';
}

Future<(ProviderContainer, SulkingApi, RestoringStore)> _pumpSettings(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  PackageInfo.setMockInitialValues(
    appName: 'The Plate',
    packageName: 'com.platepatch.app',
    version: '1.4.6',
    buildNumber: '14',
    buildSignature: '',
  );

  // A device token has to be present, or the server call the bug lives in is
  // skipped before it can throw.
  SharedPreferences.setMockInitialValues(const {
    'onboarded': true,
    'device_token': 'dev_fake',
  });

  final api = SulkingApi();
  final store = RestoringStore();
  final container = ProviderContainer(overrides: [
    prefsRepositoryProvider
        .overrideWithValue(PrefsRepository(await SharedPreferences.getInstance())),
    catalogProvider.overrideWithValue(const Catalog(foods: [], additions: [])),
    purchasesServiceProvider.overrideWithValue(store),
    scanApiProvider.overrideWithValue(api),
  ]);
  addTearDown(container.dispose);
  await container.read(proProvider.notifier).init();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(), home: const SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (container, api, store);
}

Future<void> _tapRestore(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Restore purchases'), 300);
  await tester.tap(find.text('Restore purchases'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Restore'));
  await tester.pumpAndSettle();
}

void main() {
  group('restore purchases', () {
    testWidgets('says what happened even when the server call behind it fails',
        (tester) async {
      // The whole point of the button is the sentence it produces. Restoring
      // also repairs the server's copy of the entitlement, and that repair was
      // allowed to throw straight through the button's own `await` — so a
      // successful restore reported nothing at all and the button looked dead.
      final (_, api, store) = await _pumpSettings(tester);
      // Launch already attempted one repair; the tap is the next one.
      final before = api.refreshes;

      await _tapRestore(tester);

      expect(store.restores, 1, reason: 'the store was actually asked');
      expect(api.refreshes, before + 1, reason: 'the server repair was attempted');
      expect(find.text('Pro restored.'), findsOneWidget,
          reason: 'a restore that worked must say so, whatever the server did');
    });

    testWidgets('the tap does not escape as an unhandled error', (tester) async {
      final (_, _, _) = await _pumpSettings(tester);

      await _tapRestore(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
