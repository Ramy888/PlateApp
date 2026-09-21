import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/food_matcher.dart';
import '../domain/models.dart';
import '../state/auth_providers.dart';
import '../state/plate_providers.dart';
import '../state/providers.dart';
import '../state/save_patch.dart';
import '../state/scan_providers.dart';
import 'icons.g.dart';
import 'paywall_screen.dart';
import 'result_screen.dart' show PatchCard;
import 'theme.dart';
import 'widgets/ai_image.dart';
import 'widgets/common.dart';
import 'widgets/plate_diagram.dart';
import 'widgets/report_sheet.dart';

/// Everything a scan produced, on one page.
///
/// This replaces three screens — confirm the reading, read the suggestion, then
/// go somewhere else again to see it on your own photo. Each was a reasonable
/// page on its own and the sequence was the problem: the thing people came for
/// was two taps past the thing they were shown, and the photo they had just
/// taken disappeared at the first step.
///
/// So the photo stays at the top and the rest of the page hangs off it. The
/// meal can be corrected in place, the suggestion changes as it is corrected,
/// and choosing a suggestion puts it on that same photo without going anywhere.
///
/// Only the scan route comes here. Building a meal by hand and describing one
/// in the chat still end on [ResultScreen]: those journeys have no photograph,
/// which is the thing this page is built around.
class ScanResultScreen extends ConsumerStatefulWidget {
  const ScanResultScreen({super.key, required this.slot});

  final MealSlot slot;

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  /// Which suggestion is showing. Null means whichever the engine put first.
  PickAngle? _chosen;

  /// Which of the two pictures is on screen. The patched one is the answer, so
  /// it leads; the photograph is one tap away for anyone checking the app read
  /// their plate correctly.
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    // The engine has not seen this meal yet: the confirm step that used to
    // hand it over is now this page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scan = ref.read(scanControllerProvider.notifier);
      scan.syncDraft(slot: widget.slot);
      // Anything the catalogue does not have is described first, so a plate of
      // pancakes gets an answer rather than a shrug. Then draw what is left.
      scan.describeUnknownFoods().whenComplete(() {
        if (mounted) _draw();
      });
    });
  }

  Patch? _patchFor(PatchResult result) {
    if (result.patches.isEmpty) return null;
    return result.patches.firstWhere(
      (p) => p.angle == (_chosen ?? result.patches.first.angle),
      orElse: () => result.patches.first,
    );
  }

  /// Draws the meal with the chosen addition on it.
  ///
  /// Fired whenever the answer changes rather than waiting to be asked: the
  /// picture *is* the answer on this page, and a button standing between the
  /// two made the suggestion look like a preview of a preview. The controller
  /// keys its cache on the foods and the addition, so going back to a
  /// suggestion already drawn costs nothing and returns instantly.
  void _draw() {
    if (!ref.read(authControllerProvider).isSignedIn) return;
    final result = ref.read(patchResultProvider);
    // Nothing recognised means nothing to draw. Asking anyway produced a
    // picture of a meal nobody had — a photographed plate of pancakes came
    // back as mash and carrots, labelled as theirs — and spent an AI meal to
    // do it.
    if (result.foods.isEmpty) return;
    final patch = _patchFor(result);
    if (patch == null) return;
    ref.read(plateVisualProvider.notifier).load(
          foodIds: result.foods.map((f) => f.id).toList(),
          additionId: patch.addition.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);
    final result = ref.watch(patchResultProvider);
    final isPro = ref.watch(proProvider).isPro;
    final visual = ref.watch(plateVisualProvider);
    final patch = _patchFor(result);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your meal'),
        actions: [
          if (!isPro)
            TextButton(
              onPressed: () =>
                  PaywallScreen.show(context, reason: 'More ways to patch this meal'),
              child: const Text('Get Pro'),
            ),
          IconButton(
            tooltip: 'Report this result',
            icon: const Icon(LucideIcons.flag),
            onPressed: () => ReportSheet.show(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xl),
          children: [
            _Pictures(
              original: scan.photo,
              patched: visual.image,
              // A plate with nothing recognised on it is never drawn, so the
              // tab that switches to it must not be offered either.
              drawable: result.foods.isNotEmpty,
              busy: visual.loading,
              showOriginal: _showOriginal,
              onPick: (original) => setState(() => _showOriginal = original),
              foods: result.foods,
              addition: patch?.addition,
            ),
            const SizedBox(height: Space.lg),

            Text('On your plate', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            _RecognisedShelf(
              foods: scan.recognized,
              onRemove: (food) =>
                  ref.read(scanControllerProvider.notifier).remove(food),
            ),
            // A chip can carry a warning colour but not a reason, and an
            // orange pill with no explanation is just a worry.
            if (scan.recognized.any((f) => !f.isMatched)) ...[
              const SizedBox(height: Space.sm),
              Text(
                'Anything outlined is not in the food list, so it will not count '
                'towards the patch.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: Space.md),

            _MissedSomething(slot: widget.slot),
            const SizedBox(height: Space.lg),

            if (result.foods.isEmpty)
              Inset(
                icon: LucideIcons.circleAlert,
                // "Add what you are eating" over a chip saying Pancakes reads
                // as the app not seeing what it plainly just read. It did see
                // it; it has no such food in its list, and only foods it knows
                // can be reasoned about.
                child: Text(
                  scan.recognized.isEmpty
                      ? 'Add what you are eating'
                      : 'None of these are in the food list yet, so there is '
                          'nothing to suggest. Add the closest thing above.',
                ),
              )
            else if (patch != null) ...[
              Text('Add one thing', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Space.sm),
              _PatchShelf(
                patches: result.patches,
                chosen: patch.angle,
                onSelect: (angle) {
                  setState(() {
                    _chosen = angle;
                    // The new answer is what someone just asked to see.
                    _showOriginal = false;
                  });
                  _draw();
                },
              ),
              const SizedBox(height: Space.lg),
              // A picture that could not be drawn has to say so. Running out of
              // allowance is the commonest reason and the least obvious: the
              // first suggestion draws, the next does nothing, and the page
              // looks broken rather than spent.
              if (visual.needsPro || visual.unavailable) ...[
                Notice(
                  visual.needsPro
                      ? 'You have used your AI meals. Subscribe to keep drawing them.'
                      : 'That picture could not be drawn. The suggestion still stands.',
                  tone: visual.needsPro ? NoticeTone.offer : NoticeTone.trouble,
                ),
                const SizedBox(height: Space.md),
              ],
              OutlinedButton.icon(
                // Same rule as the manual page: the plate someone is watching
                // appear is the one they mean to keep.
                onPressed: visual.loading
                    ? null
                    : () => savePatch(
                  context,
                  ref,
                  slot: widget.slot,
                  foodIds: result.foods.map((f) => f.id).toList(),
                  addition: patch.addition,
                  gapIds: result.gaps.map((g) => g.id).toList(),
                  image: visual.image,
                ),
                icon: const Icon(LucideIcons.bookmark, size: 18),
                label: Text(
                  visual.loading ? 'Drawing your plate…' : 'Save to my plates',
                ),
              ),
            ] else
              const Inset(
                icon: LucideIcons.circleCheck,
                child: Text('Nothing to add — this plate already covers the basics.'),
              ),

            // Last on the page, under the actions.
            //
            // It used to sit between the meal and the suggestions, interrupting
            // the one reading someone actually came for. A disclosure has to be
            // present and unmissable, not in the way: at the foot it is the
            // last thing read, and the first place anyone looks for it.
            const SizedBox(height: Space.xl),
            const _AiNote(),
          ],
        ),
      ),
    );
  }
}

/// The two pictures of this meal, and the tabs that choose between them.
///
/// Two, because they answer different questions. The drawn plate is the
/// suggestion — what the meal becomes — and leads, because it is what the page
/// is for. The photograph is the evidence: it is how someone checks the app
/// read their plate correctly before trusting anything it says about it.
///
/// Tabs rather than a toggle so both are visible as choices at rest. A single
/// "show original" button hides the fact that there are two pictures at all
/// until you press it.
class _Pictures extends StatelessWidget {
  const _Pictures({
    required this.original,
    required this.patched,
    required this.drawable,
    required this.busy,
    required this.showOriginal,
    required this.onPick,
    required this.foods,
    required this.addition,
  });

  final Uint8List? original;
  final Uint8List? patched;

  /// Whether there is a patched plate to show at all.
  final bool drawable;

  final bool busy;
  final bool showOriginal;

  /// True asks for the photograph.
  final ValueChanged<bool> onPick;

  final List<FoodItem> foods;
  final Addition? addition;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The photograph tab only exists when there is a photograph. This page
        // is also reached with none.
        if (original != null && drawable) ...[
          _Tabs(showOriginal: showOriginal, onPick: onPick),
          const SizedBox(height: Space.sm),
        ],
        // Not wrapped in a fixed height: the drawn plate carries a caption
        // under it, and forcing the pair into the image's own height clipped
        // the sentence that says the picture is illustrative.
        if (showOriginal && original != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusSmall),
            child: SizedBox(
              height: 260,
              width: double.infinity,
              child: Image.memory(original!, fit: BoxFit.cover),
            ),
          )
        else
          _Patched(
            image: patched,
            busy: busy,
            foods: foods,
            addition: addition,
          ),
      ],
    );
  }
}

/// The drawn plate, or what stands in for it.
///
/// Never a bare spinner: the diagram is drawn from the catalogue on the phone
/// and is on screen before the request has left it, so there is always a
/// picture of the answer even when the generated one is still coming, has
/// failed, or was never allowed.
class _Patched extends StatelessWidget {
  const _Patched({
    required this.image,
    required this.busy,
    required this.foods,
    required this.addition,
  });

  final Uint8List? image;
  final bool busy;
  final List<FoodItem> foods;
  final Addition? addition;

  @override
  Widget build(BuildContext context) {
    if (image != null) return AiImage(bytes: image!, height: 260);

    return SizedBox(
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PlateDiagram(foods, addition: addition),
          if (busy) const Positioned(bottom: 0, child: _Working()),
        ],
      ),
    );
  }
}

/// Two tabs, sitting on the page rather than in an app bar.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.showOriginal, required this.onPick});

  final bool showOriginal;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PlateColors.card,
        borderRadius: BorderRadius.circular(kPill),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Tab(
              label: 'With the addition',
              selected: !showOriginal,
              onTap: () => onPick(false),
            ),
          ),
          Expanded(
            child: _Tab(
              label: 'Your photo',
              selected: showOriginal,
              onTap: () => onPick(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(kPill);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? PlateColors.green : Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? PlateColors.neutral100 : PlateColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the app says while the picture is being made.
class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: PlateColors.neutral100,
          ),
        ),
        const SizedBox(width: Space.sm),
        Text(
          'Putting it on your plate…',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: PlateColors.neutral100),
        ),
      ],
    );
  }
}

/// What the model read, two rows deep and scrolling sideways.
///
/// Two rows rather than one because a photographed meal is usually four to six
/// things, and a single row of those either wraps into a wall or scrolls so far
/// that the end of the meal is off-screen. Two rows halves the distance.
class _RecognisedShelf extends StatelessWidget {
  const _RecognisedShelf({required this.foods, required this.onRemove});

  final List<RecognizedFood> foods;
  final ValueChanged<RecognizedFood> onRemove;

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) {
      return const Inset(
        icon: LucideIcons.circleAlert,
        child: Text('Nothing on the plate yet. Add what you are eating below.'),
      );
    }

    // Down the columns, not along the rows: reading order stays top-left to
    // bottom-left then across, which is how a two-row shelf is actually read.
    final columns = <List<RecognizedFood>>[];
    for (var i = 0; i < foods.length; i += 2) {
      columns.add(foods.sublist(i, (i + 2).clamp(0, foods.length)));
    }

    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: columns.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (_, i) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final food in columns[i]) ...[
              _FoodChip(food: food, onRemove: () => onRemove(food)),
              if (food != columns[i].last) const SizedBox(height: Space.sm),
            ],
          ],
        ),
      ),
    );
  }
}

/// One thing the model saw, and a way to say it was wrong.
class _FoodChip extends StatelessWidget {
  const _FoodChip({required this.food, required this.onRemove});

  final RecognizedFood food;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // A food the catalogue does not know cannot affect the suggestion, and
    // saying so quietly is better than letting someone believe it counted.
    final known = food.isMatched;

    return Material(
      color: known ? PlateColors.card : PlateColors.proSoft,
      borderRadius: BorderRadius.circular(kPill),
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kPill),
          border: Border.all(
            color: known ? Colors.transparent : PlateColors.warn,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              catalogIcon(food.icon),
              size: 17,
              color: known ? PlateColors.green : PlateColors.pro,
            ),
            const SizedBox(width: Space.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                food.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: PlateColors.ink),
              ),
            ),
            IconButton(
              tooltip: 'Remove ${food.displayName}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(LucideIcons.x, size: 17, color: PlateColors.inkSoft),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// The way back to the full catalogue, folded away until it is wanted.
///
/// Collapsed by default because the common case is that the reading was right.
/// It has to be visible, though: a model that missed the chicken and cannot be
/// told so is worse than no model.
class _MissedSomething extends ConsumerWidget {
  const _MissedSomething({required this.slot});

  final MealSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlateCard.quiet(
      padding: EdgeInsets.zero,
      child: Theme(
        // The default divider lines cut the card in half and make it read as
        // two things.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Lead(LucideIcons.plus),
          title: Text(
            'Did it miss something?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add anything on your plate the photo did not show.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: Space.sm),
            _Catalogue(slot: slot),
          ],
        ),
      ),
    );
  }
}

/// The suggestions, side by side.
class _PatchShelf extends StatelessWidget {
  const _PatchShelf({
    required this.patches,
    required this.chosen,
    required this.onSelect,
  });

  final List<Patch> patches;
  final PickAngle chosen;
  final ValueChanged<PickAngle> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: patches.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (_, i) {
          final patch = patches[i];
          return SizedBox(
            width: 220,
            child: PatchCard(
              patch: patch,
              selected: patch.angle == chosen,
              onTap: () => onSelect(patch.angle),
            ),
          );
        },
      ),
    );
  }
}

/// The same food list the manual builder uses, so there is one catalogue in
/// the app rather than two that can drift apart.
class _Catalogue extends ConsumerWidget {
  const _Catalogue({required this.slot});

  final MealSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final isPro = ref.watch(proProvider).isPro;
    final already = ref
        .watch(scanControllerProvider)
        .recognized
        .map((f) => f.food?.id)
        .whereType<String>()
        .toSet();

    final options = catalog
        .foodsForSlot(slot)
        .where((f) => (f.isFree || isPro) && !already.contains(f.id))
        .toList();

    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final food in options)
          PlateChip(
            icon: catalogIcon(food.icon),
            label: food.name,
            onTap: () => ref.read(scanControllerProvider.notifier).add(food),
          ),
      ],
    );
  }
}

/// The disclosure Play expects, in the place it actually matters.
///
/// It moved here with the rest of the confirm screen. Two promises live in this
/// paragraph — that the reading is machine-made and fallible, and what happened
/// to the photograph — and a page that shows a recognised meal without them is
/// a page that quietly breaks both.
class _AiNote extends StatelessWidget {
  const _AiNote();

  @override
  Widget build(BuildContext context) {
    return PlateCard.quiet(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.sparkles, size: 17, color: PlateColors.green),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Recognised by AI, which gets things wrong. Your photo was cropped '
              'and stripped of location data on this phone, and is not stored on '
              'our servers.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
