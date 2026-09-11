import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../icons.g.dart';
import '../theme.dart';

/// Where one thing sits on the drawn plate.
///
/// A value rather than a widget so the arrangement can be tested without
/// pumping anything: the engine that chose the addition is a pure function and
/// says so in its own doc comment, and a drawing of its answer that shuffled
/// between builds would quietly break that promise.
@immutable
class PlateSlot {
  const PlateSlot({required this.dx, required this.dy, required this.scale});

  /// Fractions of the plate's radius from its centre, y down.
  final double dx;
  final double dy;

  /// Relative size, so a crowded plate shrinks rather than overlaps.
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is PlateSlot && other.dx == dx && other.dy == dy && other.scale == scale;

  @override
  int get hashCode => Object.hash(dx, dy, scale);
}

/// How many foods are drawn before the rest become a count.
///
/// Six discs on a circle is the point where they stop being food and start
/// being a pattern. Past five, the sixth slot says "+N" instead.
const int kPlateMaxFoods = 5;

/// Arranges [count] things on a plate.
///
/// Pure, and deliberately so — same count, same arrangement, every time.
///
/// One thing sits in the middle, because a lone disc pushed to the edge of an
/// empty plate looks like a mistake. Two sit side by side. Three or more take a
/// ring starting at the top and going clockwise, which is how a plate is read.
List<PlateSlot> arrangeOnPlate(int count) {
  if (count <= 0) return const [];
  if (count == 1) return const [PlateSlot(dx: 0, dy: 0, scale: 1)];
  if (count == 2) {
    return const [
      PlateSlot(dx: -0.42, dy: 0, scale: 0.94),
      PlateSlot(dx: 0.42, dy: 0, scale: 0.94),
    ];
  }

  // The ring pulls in and the discs shrink as the plate fills, so six things
  // sit on a plate rather than on top of each other.
  final radius = count <= 4 ? 0.46 : 0.52;
  final scale = switch (count) {
    3 => 0.90,
    4 => 0.84,
    5 => 0.78,
    _ => 0.72,
  };

  return [
    for (var i = 0; i < count; i++)
      () {
        final angle = -math.pi / 2 + (2 * math.pi * i) / count;
        return PlateSlot(
          dx: radius * math.cos(angle),
          dy: radius * math.sin(angle),
          scale: scale,
        );
      }(),
  ];
}

/// The meal, drawn, with the addition landing on it.
///
/// This is the free tier's picture. The generated photograph is better and
/// costs money; this costs nothing, needs no account and no network, and it is
/// on screen before the request for the photograph has left the phone.
///
/// Nothing here is quantitative. No portions, no proportions, no sizes that
/// mean anything — the app may not imply a measured amount, and a drawing of a
/// plate is exactly where that would slip in unnoticed.
class PlateDiagram extends StatefulWidget {
  const PlateDiagram(this.foods, {super.key, this.addition});

  final List<FoodItem> foods;

  /// The thing being suggested. Drawn last, and in the patch line's own sage,
  /// so the eye ties the two together.
  final Addition? addition;

  @override
  State<PlateDiagram> createState() => _PlateDiagramState();
}

class _PlateDiagramState extends State<PlateDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One shot, never a loop. Three times this codebase has hung its own test
    // suite on an animation that repeated forever, and reduced motion is the
    // same answer as the accessibility one: draw the end state and stop.
    if (MediaQuery.disableAnimationsOf(context)) {
      _run.value = 1;
    } else if (!_run.isAnimating && _run.value == 0) {
      _run.forward();
    }
  }

  @override
  void didUpdateWidget(PlateDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different suggestion is a different answer, so it lands again. The
    // same one re-rendering for any other reason does not.
    if (oldWidget.addition?.id != widget.addition?.id) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _run.value = 1;
      } else {
        _run.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.foods.take(kPlateMaxFoods).toList();
    final overflow = widget.foods.length - shown.length;
    final tiles = shown.length + (overflow > 0 ? 1 : 0);
    final slots = arrangeOnPlate(tiles + (widget.addition != null ? 1 : 0));

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        // PlateDish insets its child by the rim, so what the slots are
        // fractions of is the well, not the dish.
        final well = size * (1 - 2 * 0.085);
        final radius = well / 2;
        final tile = well * 0.27;

        return Center(
          child: PlateDish(
            size: size,
            child: AnimatedBuilder(
              animation: _run,
              builder: (context, _) {
                // Two curves, not one. easeOutBack overshoots past 1 — that
                // is what gives the addition its settle — and feeding an
                // overshoot into Opacity asserts in debug. So the same raw
                // progress drives a bounded curve for fade and an
                // overshooting one for movement.
                final foods = (_run.value / 0.45).clamp(0.0, 1.0);
                final added = ((_run.value - 0.42) / 0.58).clamp(0.0, 1.0);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = 0; i < tiles; i++)
                      _positioned(
                        slot: slots[i],
                        radius: radius,
                        tile: tile,
                        fade: Curves.easeOut.transform(foods),
                        travel: Curves.easeOut.transform(foods),
                        // They arrive together, not one by one: this is the
                        // meal the person already has, not a sequence of
                        // events.
                        child: i < shown.length
                            ? _Tile(icon: catalogIcon(shown[i].icon))
                            : _Tile.count(overflow),
                      ),
                    if (widget.addition != null)
                      _positioned(
                        slot: slots.last,
                        radius: radius,
                        tile: tile,
                        fade: Curves.easeOut.transform(added),
                        travel: Curves.easeOutBack.transform(added),
                        child: _Tile(
                          icon: catalogIcon(widget.addition!.icon),
                          added: true,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _positioned({
    required PlateSlot slot,
    required double radius,
    required double tile,
    required double fade,
    required double travel,
    required Widget child,
  }) {
    final side = tile * slot.scale;
    // Everything drifts in from a little outside its place, so the plate
    // assembles rather than blinking into existence. `travel` may pass 1 on
    // the way to settling; `fade` never does.
    final settle = 1 - travel;
    return Transform.translate(
      offset: Offset(
        slot.dx * radius * (1 + settle * 0.18),
        slot.dy * radius * (1 + settle * 0.18) + settle * 6,
      ),
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: SizedBox(width: side, height: side, child: child),
      ),
    );
  }
}

/// One thing on the plate.
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, this.added = false}) : count = null;

  const _Tile.count(this.count) : icon = null, added = false;

  final IconData? icon;
  final int? count;

  /// The suggestion wears the patch line's colours; the meal wears the app's
  /// ordinary ones. One of these is the answer and the rest are the question.
  final bool added;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: added ? PlateColors.green : PlateColors.card,
          ),
          alignment: Alignment.center,
          child: count != null
              ? Text(
                  '+$count',
                  style: TextStyle(
                    fontSize: side * 0.34,
                    fontWeight: FontWeight.w700,
                    color: PlateColors.inkSoft,
                  ),
                )
              : Icon(
                  icon,
                  size: side * 0.52,
                  color: added ? PlateColors.neutral100 : PlateColors.green,
                ),
        );
      },
    );
  }
}

/// A dinner plate seen from above, lit from the upper left.
///
/// Four layers, which is what it takes for a circle to read as a dish: the
/// shadow it casts on the table, the rim, the well, and the step between them.
/// [child] sits inside the well, inset by the rim, so a full plate still has a
/// rim. Every measurement is a fraction of [size], so one of these costs the
/// same in a 54pt list thumbnail as in a 300pt hero.
///
/// The trick worth knowing: **the well is lit from the corner opposite the
/// rim.** On a real dish the near wall turns away from the light and the far
/// wall catches it. Light both from the top left and you get something
/// convincingly three-dimensional and convincingly the wrong shape — a ball
/// bearing rather than a bowl.
class PlateDish extends StatelessWidget {
  const PlateDish({
    super.key,
    required this.size,
    this.child,
    this.porcelain = const Color(0xFFFFFDF8),
    this.shade = PlateColors.neutral300,
    this.ink = PlateColors.ink,
  });

  final double size;
  final Widget? child;

  /// Where the light lands.
  final Color porcelain;

  /// Where it does not. A warm neutral, never a grey — against a cream ground
  /// a true grey reads as dirty rather than shaded.
  final Color shade;

  /// What the shadows are made of. Tinted, never black.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final rim = size * 0.085;

    return SizedBox(
      height: size,
      width: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // The rim: convex, so it catches the light at the top left.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [porcelain, shade],
            stops: const [0.15, 1.0],
          ),
          boxShadow: [
            // Contact: tight, where the plate meets the table.
            BoxShadow(
              color: ink.withValues(alpha: 0.16),
              blurRadius: size * 0.06,
              offset: Offset(0, size * 0.02),
            ),
            // Cast: wider, and what gives the height. Kept tight, or the plate
            // floats instead of sitting.
            BoxShadow(
              color: ink.withValues(alpha: 0.09),
              blurRadius: size * 0.13,
              offset: Offset(0, size * 0.06),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(rim),
          // The step down from rim to well. Without a hard edge the two
          // gradients blend and the whole thing goes soft again.
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ink.withValues(alpha: 0.07), width: 1.2),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The well: concave, so it is lit from the opposite corner.
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(0.45, 0.55),
                      radius: 1.1,
                      colors: [porcelain, shade],
                    ),
                  ),
                ),
                if (child != null) ClipOval(child: child),
                // The shadow the rim casts into the well. Last, so it falls
                // across the food as well as the porcelain.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ink.withValues(alpha: 0.20),
                          ink.withValues(alpha: 0.04),
                          const Color(0x00000000),
                        ],
                        stops: const [0.0, 0.30, 0.62],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
