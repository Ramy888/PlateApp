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
import 'package:platepatch/domain/models.dart';
import 'package:platepatch/state/chat_providers.dart';
import 'package:platepatch/state/providers.dart';
import 'package:platepatch/state/scan_providers.dart';
import 'package:platepatch/ui/chat_screen.dart';
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

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeScanApi api, {
  Map<String, Object> prefs = const {'onboarded': true, 'device_token': 'dv_fake'},
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final repo = PrefsRepository(await SharedPreferences.getInstance());
  final container = ProviderContainer(
    overrides: [
      prefsRepositoryProvider.overrideWithValue(repo),
      catalogProvider.overrideWithValue(_realCatalog()),
      purchasesServiceProvider.overrideWithValue(InertPurchasesService()),
      scanApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(), home: const ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _say(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Send'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens with an invitation, not an empty box', (tester) async {
    await _pump(tester, FakeScanApi());
    expect(find.textContaining('Tell me what you are eating'), findsOneWidget);
  });

  testWidgets('a message gets a reply, and both stay in the thread', (tester) async {
    final api = FakeScanApi();
    await _pump(tester, api);

    await _say(tester, 'rice and grilled chicken');

    expect(api.chatMessages, ['rice and grilled chicken']);
    expect(find.text('rice and grilled chicken'), findsOneWidget);
    expect(find.text('Rice and chicken.'), findsOneWidget);
  });

  testWidgets('an empty message is not sent', (tester) async {
    final api = FakeScanApi();
    await _pump(tester, api);
    await _say(tester, '   ');
    expect(api.chatMessages, isEmpty);
  });

  testWidgets('a reply carries the AI label whenever it has a picture',
      (tester) async {
    final api = FakeScanApi()
      ..chatReply = ChatReply(
        messageId: 'm1',
        reply: 'Rice it is.',
        foodIds: const ['white_rice'],
        additionId: 'side_salad',
        imageUrl: 'https://api.example/v1/preview/abc.jpg',
        disclaimer: 'AI visual preview — appearance and serving size are illustrative.',
        quota: FakeScanApi().quotaValue,
      )
      ..previewBytes = Uint8List.fromList(_onePixelPng);

    await _pump(tester, api);
    await _say(tester, 'rice');

    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('AI picture'), findsOneWidget);
  });

  // Play requires generated content to be rateable. If this disappears, so
  // does the compliance.
  testWidgets('every reply can be rated and reported', (tester) async {
    final api = FakeScanApi();
    await _pump(tester, api);
    await _say(tester, 'rice');

    expect(find.byTooltip('Helpful'), findsOneWidget);
    expect(find.byTooltip('Not helpful'), findsOneWidget);
    expect(find.byTooltip('Report this reply'), findsOneWidget);
  });

  testWidgets('a thumb reaches the server and sticks', (tester) async {
    final api = FakeScanApi();
    final container = await _pump(tester, api);
    await _say(tester, 'rice');

    await tester.tap(find.byTooltip('Not helpful'));
    await tester.pumpAndSettle();

    expect(api.ratings, [('msg_fake', false)]);
    final reply = container
        .read(chatControllerProvider)
        .messages
        .lastWhere((m) => !m.isUser);
    expect(reply.rating, isFalse);
  });

  testWidgets('a rated reply cannot be rated again', (tester) async {
    final api = FakeScanApi();
    await _pump(tester, api);
    await _say(tester, 'rice');

    await tester.tap(find.byTooltip('Helpful'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Not helpful'));
    await tester.pumpAndSettle();

    expect(api.ratings, [('msg_fake', true)]);
  });

  testWidgets('a failure is said in the thread, not thrown away', (tester) async {
    final api = FakeScanApi()
      ..chatFailure = const ScanFailure(ScanError.busy, 'The assistant is busy.');
    await _pump(tester, api);

    await _say(tester, 'rice');
    expect(find.text('The assistant is busy.'), findsOneWidget);
    // The message the user typed is still there to try again from.
    expect(find.text('rice'), findsOneWidget);
  });

  testWidgets('the conversation survives a restart', (tester) async {
    final api = FakeScanApi();
    final container = await _pump(tester, api);
    await _say(tester, 'rice');

    final saved = container.read(prefsRepositoryProvider).chatJson;
    expect(saved.length, 2);

    // A fresh container reading the same prefs is what a relaunch looks like.
    final reopened = await _pump(
      tester,
      FakeScanApi(),
      prefs: {
        'onboarded': true,
        'device_token': 'dv_fake',
        'chat': saved,
      },
    );
    expect(reopened.read(chatControllerProvider).messages.length, 2);
  });

  testWidgets('deleting everything takes the conversation with it',
      (tester) async {
    final api = FakeScanApi();
    final container = await _pump(tester, api);
    await _say(tester, 'rice');
    expect(container.read(chatControllerProvider).messages, isNotEmpty);

    await container.read(scanControllerProvider.notifier).deleteEverything();

    expect(container.read(chatControllerProvider).messages, isEmpty);
    expect(container.read(prefsRepositoryProvider).chatJson, isEmpty);
  });

  testWidgets('a corrupt saved row is dropped rather than crashing',
      (tester) async {
    final container = await _pump(
      tester,
      FakeScanApi(),
      prefs: {
        'onboarded': true,
        'device_token': 'dv_fake',
        'chat': <String>['{not json', '{"id":"a","author":"user","text":"rice"}'],
      },
    );
    expect(container.read(chatControllerProvider).messages.length, 1);
  });
}

/// The smallest valid PNG, so Image.memory has something real to decode.
const _onePixelPng = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
  0x42, 0x60, 0x82,
];
