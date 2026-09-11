import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platepatch/domain/models.dart';
import 'package:platepatch/ui/icons.g.dart';
import 'package:platepatch/ui/theme.dart';
import 'package:platepatch/ui/widgets/plate_diagram.dart';

FoodItem _food(String id) => FoodItem(
      id: id,
      name: id,
      emoji: '',
      icon: 'wheat',
      group: 'grains',
      slots: const {MealSlot.lunchDinner},
      provides: const NutrientScores(),
      tags: const {},
    );

Addition _add(String id, String icon) => Addition(
      id: id,
      name: id,
      emoji: '',
      icon: icon,
      provides: const NutrientScores(),
      speed: 1,
      cost: 1,
      tags: const {},
      slots: const {MealSlot.lunchDinner},
      how: 'Some of it.',
    );

final _addition = _add('side_salad', 'salad');

Future<void> _pump(
  WidgetTester tester, {
  required List<FoodItem> foods,
  Addition? addition,
  bool animate = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: !animate),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 220,
            child: PlateDiagram(foods, addition: addition),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('arrangeOnPlate', () {
    test('puts a single thing in the middle', () {
      // A lone disc pushed to the edge of an empty plate reads as a mistake.
      expect(arrangeOnPlate(1), const [PlateSlot(dx: 0, dy: 0, scale: 1)]);
    });

    test('sits a pair side by side, not on a ring', () {
      final slots = arrangeOnPlate(2);
      expect(slots, hasLength(2));
      expect(slots[0].dy, 0);
      expect(slots[1].dy, 0);
      expect(slots[0].dx, lessThan(0));
      expect(slots[1].dx, greaterThan(0));
    });

    test('starts the ring at the top and goes clockwise', () {
      final slots = arrangeOnPlate(4);
      // First slot straight up: a plate is read from the top.
      expect(slots.first.dx, closeTo(0, 0.001));
      expect(slots.first.dy, lessThan(0));
      // Second a quarter turn clockwise, which is to the right.
      expect(slots[1].dx, greaterThan(0));
      expect(slots[1].dy, closeTo(0, 0.001));
    });

    test('shrinks the pieces as the plate fills', () {
      expect(arrangeOnPlate(3).first.scale,
          greaterThan(arrangeOnPlate(6).first.scale));
    });

    test('keeps everything inside the plate', () {
      for (var n = 1; n <= 8; n++) {
        for (final slot in arrangeOnPlate(n)) {
          final r = slot.dx * slot.dx + slot.dy * slot.dy;
          expect(r, lessThanOrEqualTo(0.55 * 0.55 + 0.0001),
              reason: '$n things: a slot fell off the plate');
        }
      }
    });

    test('is deterministic, because the engine it draws is', () {
      // Same plate, same answer, same drawing. The engine's determinism is a
      // product requirement; a picture of it that shuffled would break that.
      for (var n = 0; n <= 7; n++) {
        expect(arrangeOnPlate(n), arrangeOnPlate(n));
      }
    });

    test('draws nothing for nothing', () {
      expect(arrangeOnPlate(0), isEmpty);
      expect(arrangeOnPlate(-1), isEmpty);
    });
  });

  group('PlateDiagram', () {
    testWidgets('draws one piece per food', (tester) async {
      await _pump(tester, foods: [_food('a'), _food('b'), _food('c')]);
      expect(find.byIcon(catalogIcon('wheat')), findsNWidgets(3));
    });

    testWidgets('caps a crowded plate and counts the rest', (tester) async {
      await _pump(tester, foods: List.generate(7, (i) => _food('f$i')));
      // Five drawn, and the rest become a number rather than a pattern.
      expect(find.byIcon(catalogIcon('wheat')), findsNWidgets(5));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('an empty plate still draws a plate', (tester) async {
      await _pump(tester, foods: const []);
      expect(find.byType(PlateDiagram), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the addition is told apart from the meal', (tester) async {
      await _pump(tester, foods: [_food('a')], addition: _addition);

      // The suggestion wears the patch line's sage; the meal wears the card.
      final circles = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .toList();
      expect(circles.where((d) => d.color == PlateColors.green), isNotEmpty,
          reason: 'the addition should be drawn in sage');
      expect(circles.where((d) => d.color == PlateColors.card), isNotEmpty,
          reason: 'the meal should be drawn in the card colour');
    });

    testWidgets('reduced motion draws the finished plate, not an animation',
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 300,
              height: 220,
              child: PlateDiagram([_food('a')], addition: _addition),
            ),
          ),
        ),
      );
      // One frame, no settling: everything is already where it belongs.
      await tester.pump();
      final opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(opacities, isNotEmpty);
      for (final o in opacities) {
        expect(o, 1.0, reason: 'nothing should still be fading in');
      }
    });

    testWidgets('animating still settles, so the suite never hangs on it',
        (tester) async {
      // The trap this codebase has fallen into three times: an animation that
      // repeats forever turns pumpAndSettle into a timeout rather than a
      // failure. This one runs once.
      await _pump(
        tester,
        foods: [_food('a'), _food('b')],
        addition: _addition,
        animate: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new suggestion lands again', (tester) async {
      await _pump(tester, foods: [_food('a')], addition: _addition);
      final other = _add('boiled_egg', 'egg');
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 300,
              height: 220,
              child: PlateDiagram(const [], addition: other),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(catalogIcon('egg')), findsOneWidget);
    });
  });
}
