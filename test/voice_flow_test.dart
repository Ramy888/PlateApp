import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:platepatch/data/auth_service.dart';
import 'package:platepatch/data/catalog.dart';
import 'package:platepatch/data/patch_images.dart';
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

  /// Every clip the screen asked to play back, and whether it is playing now.
  final played = <VoiceClip>[];
  bool playing = false;
  final _finished = StreamController<void>.broadcast();

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> startRecording() async => started++;

  @override
  Future<VoiceClip?> stopRecording() async => clipBytes == 0
      ? null
      : VoiceClip(bytes: Uint8List(clipBytes), mimeType: 'audio/mp4');

  @override
  Future<void> playClip(VoiceClip clip) async {
    played.add(clip);
    playing = true;
  }

  @override
  Future<void> stopPlayback() async => playing = false;

  @override
  Stream<void> get playbackFinished => _finished.stream;

  /// Lets a test end playback the way the speaker would.
  void finishPlayback() {
    playing = false;
    _finished.add(null);
  }

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
      patchImagesProvider.overrideWithValue(MemoryPatchImages()),
      catalogProvider.overrideWithValue(_realCatalog()),
      purchasesServiceProvider.overrideWithValue(InertPurchasesService()),
      authServiceProvider.overrideWithValue(InertAuthService()),
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

  group('hearing yourself back', () {
    testWidgets('offers the recording once the answer is in', (tester) async {
      // "Did it mishear me, or misunderstand me?" is the first question when
      // an answer looks wrong, and until now there was no way to tell.
      final voice = FakeVoiceService();
      await _pump(tester, FakeScanApi(), voice);

      expect(find.text('Hear what you said'), findsNothing);
      await _hold(tester);
      expect(find.text('Hear what you said'), findsOneWidget);
    });

    testWidgets('plays the clip that was actually sent', (tester) async {
      final api = FakeScanApi();
      final voice = FakeVoiceService();
      await _pump(tester, api, voice);
      await _hold(tester);

      await tester.tap(find.text('Hear what you said'));
      await tester.pumpAndSettle();

      expect(voice.played, hasLength(1));
      expect(voice.played.single.bytes.length, 8192);
      expect(find.text('Playing what you said'), findsOneWidget);
    });

    testWidgets('a second tap stops it', (tester) async {
      final voice = FakeVoiceService();
      await _pump(tester, FakeScanApi(), voice);
      await _hold(tester);

      await tester.tap(find.text('Hear what you said'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playing what you said'));
      await tester.pumpAndSettle();

      expect(voice.playing, isFalse);
      expect(find.text('Hear what you said'), findsOneWidget);
    });

    testWidgets('reaching the end puts the button back', (tester) async {
      final voice = FakeVoiceService();
      await _pump(tester, FakeScanApi(), voice);
      await _hold(tester);
      await tester.tap(find.text('Hear what you said'));
      await tester.pumpAndSettle();

      voice.finishPlayback();
      await tester.pumpAndSettle();

      expect(find.text('Hear what you said'), findsOneWidget);
    });

    testWidgets('speaking again drops the old recording', (tester) async {
      // The control must never offer to play back a different meal than the
      // one on screen.
      final voice = FakeVoiceService();
      await _pump(tester, FakeScanApi(), voice);
      await _hold(tester);
      expect(find.text('Hear what you said'), findsOneWidget);

      // Not GestureDetector.first: once an answer is on screen its picture is
      // tappable too, and the mic is no longer the first one in the tree.
      final mic = find.ancestor(
        of: find.byIcon(LucideIcons.mic),
        matching: find.byType(GestureDetector),
      );
      final gesture = await tester.startGesture(tester.getCenter(mic.first));
      // Discrete pumps, never pumpAndSettle: the button animates while it is
      // listening, so settling never returns with a finger down. The recorder
      // is asked asynchronously, so a few frames have to pass first.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Hear what you said'), findsNothing);

      // Released with discrete pumps for the same reason, and the turn is
      // allowed to finish so the widget is not torn down mid-flight.
      await gesture.up();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
  });
}
