import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/models.dart';
import '../state/auth_providers.dart';
import '../state/plate_providers.dart';
import '../state/providers.dart';
import '../state/save_patch.dart';
import '../state/scan_providers.dart';
import 'icons.g.dart';
import 'paywall_screen.dart';
import 'preview_screen.dart';
import 'theme.dart';
import 'widgets/plate_diagram.dart';
import 'widgets/common.dart';
import 'widgets/report_sheet.dart';
import 'widgets/sign_in_sheet.dart';

/// The answer.
///
/// Everything else in this app is a way of getting here, so this page is
/// allowed to be the largest thing in it: the plate drawn with the addition on
/// it, the addition said in words, why it was chosen, and one button to take
/// it. The other two suggestions sit underneath, because a single answer with
/// no alternative reads as a decision made for you.
///
/// It must read with no network at all. The engine's answer is the page; the
/// picture and the written sentence are what get added when they can be.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  /// Which of the three is showing. Null means the first one the engine chose.
  PickAngle? _chosen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _draw());
  }

  /// The words are the engine's and always free; only the picture costs
  /// anything, so a guest sees the whole answer and the offer to draw it.
  void _draw() {
    if (!ref.read(authControllerProvider).isSignedIn) return;
    final result = ref.read(patchResultProvider);
    final patch = _patchFor(result);
    if (patch == null) return;
    ref.read(plateVisualProvider.notifier).load(
          foodIds: result.foods.map((f) => f.id).toList(),
          additionId: patch.addition.id,
        );
  }

  Future<void> _drawAfterSignIn() async {
    if (!await requireSignIn(context, ref, reason: 'See your plate drawn')) return;
    _draw();
  }

  Patch? _patchFor(PatchResult result) {
    if (result.patches.isEmpty) return null;
    return result.patches.firstWhere(
      (p) => p.angle == (_chosen ?? result.patches.first.angle),
      orElse: () => result.patches.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(patchResultProvider);
    final visual = ref.watch(plateVisualProvider);
    final isPro = ref.watch(proProvider).isPro;
    final patch = _patchFor(result);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your patch'),
        actions: [
          // Up here rather than in a card at the foot of the page. The old
          // card sat below the answer, competed with the save button, and was
          // the last thing anyone read — a label costs nothing and is always
          // in reach.
          if (!isPro)
            TextButton(
              onPressed: () =>
                  PaywallScreen.show(context, reason: 'More ways to patch this meal'),
              child: const Text('Get Pro'),
            ),
          // Play requires in-app reporting wherever an AI-derived result shows.
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
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
          children: [
            _OnYourPlate(foods: result.foods),
            const SizedBox(height: Space.md),
            Text(result.headline, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.lg),

            if (result.isBalanced)
              const _Balanced()
            else if (patch == null)
              _NoSuggestions(isPro: isPro)
            else ...[
              // The choice comes before the picture, because the picture is of
              // whatever is chosen. Reading order now matches cause and
              // effect: what is light, which fix, then what it looks like.
              if (result.patches.length > 1) ...[
                _PatchPicker(
                  patches: result.patches,
                  selected: patch.angle,
                  onSelect: (angle) {
                    if (angle == patch.angle) return;
                    setState(() => _chosen = angle);
                    _draw();
                  },
                ),
                const SizedBox(height: Space.lg),
              ],
              _Hero(
                patch: patch,
                foods: result.foods,
                visual: visual,
                signedIn: ref.watch(authControllerProvider).isSignedIn,
                onDraw: _drawAfterSignIn,
              ),
              const SizedBox(height: Space.md),
              PatchHighlight(
                icon: catalogIcon(patch.addition.icon),
                name: patch.addition.name,
                how: patch.addition.how,
              ),
              const SizedBox(height: Space.md),
              _Why(result: result, patch: patch, caption: visual.caption),
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: () => savePatch(
                  context,
                  ref,
                  slot: result.slot,
                  foodIds: result.foods.map((f) => f.id).toList(),
                  addition: patch.addition,
                  gapIds: result.gaps.map((g) => g.id).toList(),
                  image: visual.image,
                ),
                child: const Text("I'll add this"),
              ),
              if (ref.watch(scanControllerProvider).photo != null) ...[
                const SizedBox(height: Space.sm),
                OutlinedButton.icon(
                  onPressed: () => isPro
                      ? Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => PreviewScreen(patch: patch),
                        ))
                      : PaywallScreen.show(context, reason: 'See your patched plate'),
                  icon: const Icon(LucideIcons.sparkles, size: 16),
                  label: const Text('Use my own photo instead'),
                ),
              ],
              if (visual.messageId.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                _Feedback(messageId: visual.messageId),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// What is on the plate, as small chips. Named rather than counted.
class _OnYourPlate extends StatelessWidget {
  const _OnYourPlate({required this.foods});

  final List<FoodItem> foods;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('On your plate', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final food in foods)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: PlateColors.card,
                  borderRadius: BorderRadius.circular(kPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(catalogIcon(food.icon), size: 14, color: PlateColors.green),
                    const SizedBox(width: 6),
                    Text(food.name, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The plate with the addition on it.
///
/// A placeholder rather than an absence when there is no picture: the page has
/// the same shape whether or not it could be drawn, so nothing jumps when one
/// arrives and nothing looks broken when one does not.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.patch,
    required this.foods,
    required this.visual,
    required this.signedIn,
    required this.onDraw,
  });

  final Patch patch;

  /// The meal, so the well can draw it while there is no photograph of it —
  /// which for a guest, or anyone out of tries, is always.
  final List<FoodItem> foods;

  final PlateVisual visual;

  /// A guest gets the whole answer in words and an offer to draw it.
  final bool signedIn;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kRadius),
          child: SizedBox(
            height: 220,
            width: double.infinity,
            // A photograph when there is one. Otherwise the plate drawn here,
            // which needs no account, no network and no allowance — so the
            // well is never empty and the free answer never looks like the
            // paid one with a hole in it.
            child: visual.image != null
                ? Image.memory(visual.image!, fit: BoxFit.cover)
                : ColoredBox(
                    color: PlateColors.card,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.md),
                      child: PlateDiagram(foods, addition: patch.addition),
                    ),
                  ),
          ),
        ),
        if (visual.image != null) ...[
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.sparkles, size: 13, color: PlateColors.inkSoft),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI picture — appearance and serving size are illustrative.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 12.5, color: PlateColors.inkSoft),
                ),
              ),
            ],
          ),
        ] else if (!signedIn) ...[
          _PhotoOffer(label: 'Sign in', onTap: onDraw),
        ] else if (visual.needsPro) ...[
          _PhotoOffer(
            label: 'Get Pro',
            onTap: () => PaywallScreen.show(context, reason: 'See your patched plate'),
          ),
        ],
      ],
    );
  }
}

/// Why this, and how much of it. The engine's reasoning first, because it is
/// the part that is always true; the written sentence is a gloss on it.
class _Why extends StatelessWidget {
  const _Why({required this.result, required this.patch, required this.caption});

  final PatchResult result;
  final Patch patch;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption.isNotEmpty) ...[
          Text(caption, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: Space.sm),
        ],
        Inset(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patch.reason, style: Theme.of(context).textTheme.bodyMedium),
              if (result.gaps.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Text(
                  result.gaps.first.benefit,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
class _Feedback extends ConsumerStatefulWidget {
  const _Feedback({required this.messageId});

  final String messageId;

  @override
  ConsumerState<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends ConsumerState<_Feedback> {
  bool? _rating;

  Future<void> _rate(bool helpful) async {
    setState(() => _rating = helpful);
    final token = ref.read(prefsRepositoryProvider).deviceToken;
    if (token == null) return;
    await ref.read(scanApiProvider).rate(
          deviceToken: token,
          messageId: widget.messageId,
          helpful: helpful,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Was this useful?', style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        IconButton(
          tooltip: 'Helpful',
          visualDensity: VisualDensity.compact,
          onPressed: _rating == null ? () => _rate(true) : null,
          icon: Icon(LucideIcons.thumbsUp,
              size: 17, color: _rating == true ? PlateColors.green : PlateColors.inkSoft),
        ),
        IconButton(
          tooltip: 'Not helpful',
          visualDensity: VisualDensity.compact,
          onPressed: _rating == null ? () => _rate(false) : null,
          icon: Icon(LucideIcons.thumbsDown,
              size: 17, color: _rating == false ? PlateColors.green : PlateColors.inkSoft),
        ),
      ],
    );
  }
}

class _Balanced extends StatelessWidget {
  const _Balanced();

  @override
  Widget build(BuildContext context) {
    return PlateCard.selected(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.partyPopper, size: 26, color: PlateColors.green),
          const SizedBox(height: Space.sm),
          Text('Nothing to patch.', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            'Protein, fibre and healthy fats are all covered here. Go and eat it.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _NoSuggestions extends StatelessWidget {
  const _NoSuggestions({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.filter, size: 26, color: PlateColors.green),
          const SizedBox(height: Space.sm),
          Text('Nothing fits your filters here.',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            isPro
                ? 'Try loosening a preference for this meal.'
                : 'Try loosening a preference, or unlock the full ingredient library in Pro.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// The three ways to fix this meal, side by side.
///
/// They used to be a vertical "Or instead" list below the answer, which read
/// as an afterthought and put the alternatives further from the thing they
/// were alternatives to. A row of cards says these are peers, and that one of
/// them is currently chosen.
class _PatchPicker extends StatelessWidget {
  const _PatchPicker({
    required this.patches,
    required this.selected,
    required this.onSelect,
  });

  final List<Patch> patches;
  final PickAngle selected;
  final ValueChanged<PickAngle> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Tall enough for two lines of addition name, which is what the longest
      // in the catalogue needs.
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: patches.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final patch = patches[i];
          return _PatchCard(
            patch: patch,
            selected: patch.angle == selected,
            onTap: () => onSelect(patch.angle),
          );
        },
      ),
    );
  }
}

class _PatchCard extends StatelessWidget {
  const _PatchCard({
    required this.patch,
    required this.selected,
    required this.onTap,
  });

  final Patch patch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        width: 168,
        child: PlateCard(
          onTap: onTap,
          color: selected ? PlateColors.greenSel : PlateColors.card,
          border: selected ? PlateColors.green : null,
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Lead(
                    catalogIcon(patch.addition.icon),
                    size: 17,
                    tone: selected ? PlateColors.neutral100 : PlateColors.green,
                    background:
                        selected ? PlateColors.green : PlateColors.neutral100,
                  ),
                  const Spacer(),
                  if (selected)
                    const Icon(LucideIcons.check, size: 17, color: PlateColors.green),
                ],
              ),
              const SizedBox(height: Space.sm),
              // The angle first and quiet — it is how you tell the three
              // apart at a glance, not what you are being offered.
              Text(
                patch.angle.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: PlateColors.inkSoft,
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Text(
                  patch.addition.name,
                  style: text.titleMedium?.copyWith(fontSize: 15, height: 1.25),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line under the drawing, offering the photograph.
///
/// It used to be two sentences explaining which parts were free. The drawing
/// is now sitting directly above it saying that far better than a sentence
/// could — what is left to say is what the photo costs, and where to get it.
class _PhotoOffer extends StatelessWidget {
  const _PhotoOffer({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'See a photo of the actual plate.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: onTap,
            // Tight, so the button sits beside the sentence rather than
            // floating away from it.
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
