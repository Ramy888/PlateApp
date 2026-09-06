import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/catalog.dart';
import 'data/prefs_repository.dart';
import 'data/purchases_service.dart';
import 'state/providers.dart';
import 'ui/meal_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/theme.dart';

/// Supplied at build time so the key never sits in the repository:
/// `flutter build appbundle --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx`
const _revenueCatAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
const _revenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both are local: bundled JSON and on-device preferences. Nothing here can
  // hang on a network call, so there is no splash screen to get stuck on.
  final prefs = await PrefsRepository.open();
  final catalog = await Catalog.load();

  final apiKey = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => _revenueCatIosKey,
    _ => _revenueCatAndroidKey,
  };

  runApp(
    ProviderScope(
      overrides: [
        prefsRepositoryProvider.overrideWithValue(prefs),
        catalogProvider.overrideWithValue(catalog),
        purchasesServiceProvider.overrideWithValue(RevenueCatService(apiKey: apiKey)),
      ],
      child: const PlatePatchApp(),
    ),
  );
}

class PlatePatchApp extends ConsumerStatefulWidget {
  const PlatePatchApp({super.key});

  @override
  ConsumerState<PlatePatchApp> createState() => _PlatePatchAppState();
}

class _PlatePatchAppState extends ConsumerState<PlatePatchApp> {
  @override
  void initState() {
    super.initState();
    // Fire and forget: entitlement state arrives when it arrives, and the app
    // is fully usable in the meantime.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(proProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlatePatch',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _RootGate(),
    );
  }
}

class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
    return onboarded ? const MealScreen() : const OnboardingScreen();
  }
}
