import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/food_matcher.dart';
import '../domain/models.dart';
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
import 'widgets/sign_in_sheet.dart';
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

  /// Whether the user has asked to see the photo as they took it.
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    // The engine has not seen this meal yet: the confirm step that used to
    // hand it over is now this page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(scanControllerProvider.notifier).syncDraft(slot: widget.slot);
    });
  }

  Patch? _patchFor(PatchResult result) {
    if (result.patches.isEmpty) return null;
    return result.patches.firstWhere(
      (p) => p.angle == (_chosen ?? result.patches.first.angle),
      orElse: () => result.patches.first,
    );
  }

  Future<void> _seeItOnMyPhoto(Patch patch) async {
    if (!await requireSignIn(context, ref, reason: 'See this on your own photo')) {
      return;
    }
    if (!mounted) return;
    setState(() => _showOriginal = false);
    await ref.read(scanControllerProvider.notifier).generatePreview(patch.addition.id);
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);
    final result = ref.watch(patchResultProvider);
    final isPro = ref.watch(proProvider).isPro;
    final patch = _patchFor(result);

    final edited = patch == null ? null : scan.previewFor(patch.addition.id);
    final busy = patch != null && scan.previewing == patch.addition.id;

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
            _Photo(
              original: scan.photo,
              edited: edited,
              busy: busy,
              showOriginal: _showOriginal,
              onToggle: () => setState(() => _showOriginal = !_showOriginal),
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
            const SizedBox(height: Space.md),
            const _AiNote(),
            const SizedBox(height: Space.lg),

            if (result.foods.isEmpty)
              const Inset(
                icon: LucideIcons.circleAlert,
                child: Text('Add what you are eating'),
              )
            else if (patch != null) ...[
              Text('Add one thing', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Space.sm),
              _PatchShelf(
                patches: result.patches,
                chosen: patch.angle,
                onSelect: (angle) {
                  // A failure about the previous suggestion is not about this
                  // one.
                  ref.read(scanControllerProvider.notifier).clearPreviewProblem();
                  setState(() {
                    _chosen = angle;
                    // A different suggestion means a different picture; the
                    // one on screen belongs to the old answer.
                    _showOriginal = false;
                  });
                },
              ),
              const SizedBox(height: Space.lg),
              // A picture that could not be made has to say so. Running out of
              // free tries is the commonest reason and the least obvious: the
              // first suggestion draws, every one after it does nothing at
              // all, and the page looks broken rather than spent.
              if (scan.previewFailure != null) ...[
                Notice(
                  scan.previewFailure!.message,
                  tone: scan.previewFailure!.error.suggestsUpgrade
                      ? NoticeTone.offer
                      : NoticeTone.trouble,
                ),
                const SizedBox(height: Space.md),
              ],
              if (edited == null)
                FilledButton.icon(
                  onPressed: busy ? null : () => _seeItOnMyPhoto(patch),
                  icon: const Icon(LucideIcons.sparkles, size: 18),
                  label: Text(busy ? 'Putting it on your plate…' : 'See it on my photo'),
                ),
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                onPressed: () => savePatch(
                  context,
                  ref,
                  slot: widget.slot,
                  foodIds: result.foods.map((f) => f.id).toList(),
                  addition: patch.addition,
                  gapIds: result.gaps.map((g) => g.id).toList(),
                  image: edited,
                ),
                icon: const Icon(LucideIcons.bookmark, size: 18),
                label: const Text('Save to my plates'),
              ),
            ] else
              const Inset(
                icon: LucideIcons.circleCheck,
                child: Text('Nothing to add — this plate already covers the basics.'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The photograph, with the suggestion on it.
///
/// The picture the user took is the anchor of this page, so it never leaves the
/// top and it is never replaced by a spinner: while an edit is being made the
/// old image stays put under a quiet marker. Blanking to a loading state here
/// would throw away the only thing on screen that is unmistakably *theirs*.
class _Photo extends StatelessWidget {
  const _Photo({
    required this.original,
    required this.edited,
    required this.busy,
    required this.showOriginal,
    required this.onToggle,
    required this.foods,
    required this.addition,
  });

  final Uint8List? original;
  final Uint8List? edited;
  final bool busy;
  final bool showOriginal;
  final VoidCallback onToggle;
  final List<FoodItem> foods;
  final Addition? addition;

  @override
  Widget build(BuildContext context) {
    final showing = (showOriginal || edited == null) ? original : edited;

    // No photograph at all — a scan that came from somewhere else. The drawn
    // plate is the free answer and stands in.
    if (showing == null) {
      return SizedBox(
        height: 220,
        child: PlateDiagram(foods, addition: addition),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            // An edit carries the AI label; the user's own photograph must not,
            // because it is not AI and saying so would be a lie in both
            // directions.
            if (!showOriginal && edited != null)
              AiImage(bytes: showing, height: 260)
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusSmall),
                child: SizedBox(
                  height: 260,
                  width: double.infinity,
                  child: Image.memory(showing, fit: BoxFit.cover),
                ),
              ),
            if (busy)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  child: ColoredBox(
                    color: PlateColors.ink.withValues(alpha: 0.42),
                    child: const Center(child: _Working()),
                  ),
                ),
              ),
          ],
        ),
        if (edited != null && !busy) ...[
          const SizedBox(height: Space.xs),
          TextButton.icon(
            onPressed: onToggle,
            icon: Icon(
              showOriginal ? LucideIcons.sparkles : LucideIcons.image,
              size: 16,
            ),
            label: Text(showOriginal ? 'Show the patched plate' : 'Show my original'),
          ),
        ],
      ],
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
