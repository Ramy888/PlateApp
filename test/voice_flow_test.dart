import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platepatch/data/catalog.dart';
import 'package:platepatch/data/prefs_repository.dart';
import 'package:platepatch/data/purchases_service.dart';
import 'package:platepatch/data/scan_api.dart';
import 'package:platepatch/data/voice_service.dart';
import 'package:platepatch/domain/models.dart';
import 'package:platepatch/state/chat_providers.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/state/scan_providers.dart';
import 'package:platepatch/ui/theme.dart';
import 'package:platepatch/ui/voice_screen.dart';
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

/// A microphone that is never there, so these tests can run on a build machine.
class FakeVoiceService implements VoiceService {
  FakeVoiceService({this.permitted = true, this.clipBytes = 8192});

  bool permitted;
  int clipBytes;

  int started = 0;
  final spoken = <String>[];
  bool stoppedSpeaking = false;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> startRecording() async => started++;

  @override
  Future<VoiceClip?> stopRecording() async => clipBytes == 0
      ? null
      : VoiceClip(bytes: Uint8List(clipBytes), mimeType: 'audio/mp4');

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async => stoppedSpeaking = true;

  @override
  Future<void> dispose() async {}
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeScanApi api,
  FakeVoiceService voice,
) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'onboarded': true, 'device_token': 'dv_fake'});
  final repo = PrefsRepository(await SharedPreferences.getInstance());
  final container = ProviderContainer(
    overrides: [
      prefsRepositoryProvider.overrideWithValue(repo),
      catalogProvider.overrideWithValue(_realCatalog()),
      purchasesServiceProvider.overrideWithValue(InertPurchasesService()),
      scanApiProvider.overrideWithValue(api),
      voiceServiceProvider.overrideWithValue(voice),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(), home: const VoiceScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Press and release the big button, the way a thumb does.
Future<void> _hold(WidgetTester tester) async {
  final button = find.byType(GestureDetector).first;
  final gesture = await tester.startGesture(tester.getCenter(button));
  await tester.pump(const Duration(milliseconds: 400));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens telling you what to do', (tester) async {
    await _pump(tester, FakeScanApi(), FakeVoiceService());
    expect(find.text('Hold and say your meal'), findsOneWidget);
    expect(find.text('Hold to talk'), findsOneWidget);
  });

  testWidgets('holding sends the recording and shows what was heard',
      (tester) async {
    final api = FakeScanApi();
    final voice = FakeVoiceService();
    await _pump(tester, api, voice);

    await _hold(tester);

    expect(voice.started, 1);
    expect(api.voiceClips, [8192]);
    expect(find.text('What I heard'), findsOneWidget);
    expect(find.text('I had rice and chicken'), findsOneWidget);
    expect(find.text('Rice and chicken.'), findsOneWidget);
  });

  // The point of speaking is not having to look at the screen.
  testWidgets('the answer is read back out loud', (tester) async {
    final voice = FakeVoiceService();
    await _pump(tester, FakeScanApi(), voice);

    await _hold(tester);

    expect(voice.spoken, ['Rice and chicken.']);
  });

  testWidgets('a refused microphone is explained, and nothing is sent',
      (tester) async {
    final api = FakeScanApi();
    final voice = FakeVoiceService(permitted: false);
    await _pump(tester, api, voice);

    await _hold(tester);

    expect(find.textContaining('needs the microphone'), findsOneWidget);
    expect(voice.started, 0);
    expect(api.voiceClips, isEmpty);
  });

  testWidgets('a clip too short to be speech is not sent', (tester) async {
    final api = FakeScanApi();
    final voice = FakeVoiceService(clipBytes: 0);
    await _pump(tester, api, voice);

    await _hold(tester);

    expect(find.textContaining('too short'), findsOneWidget);
    expect(api.voiceClips, isEmpty);
  });

  testWidgets('a failure is said, not swallowed', (tester) async {
    final api = FakeScanApi()
      ..chatFailure = const ScanFailure(ScanError.busy, 'The assistant is busy.');
    await _pump(tester, api, FakeVoiceService());

    await _hold(tester);

    expect(find.text('The assistant is busy.'), findsOneWidget);
  });

  // Play requires generated content to be rateable and reportable, whichever
  // way it was asked for.
  testWidgets('a spoken reply can be rated and reported', (tester) async {
    await _pump(tester, FakeScanApi(), FakeVoiceService());
    await _hold(tester);

    expect(find.byTooltip('Helpful'), findsOneWidget);
    expect(find.byTooltip('Not helpful'), findsOneWidget);
    expect(find.byTooltip('Report this reply'), findsOneWidget);
  });

  testWidgets('a spoken turn joins the same conversation as a typed one',
      (tester) async {
    final container = await _pump(tester, FakeScanApi(), FakeVoiceService());
    await _hold(tester);

    final messages = container.read(chatControllerProvider).messages;
    expect(messages.length, 2);
    expect(messages.first.isUser, isTrue);
    expect(messages.first.spoken, isTrue);
    // And it persists, so the chat screen shows it after a restart.
    expect(container.read(prefsRepositoryProvider).chatJson.length, 2);
  });
}
