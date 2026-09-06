import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'check_screen.dart';
import 'paywall_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/report_sheet.dart';

/// "Your PlatePatch" — what may be missing, and the three things to add.
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(patchResultProvider);
    final draft = ref.watch(mealDraftProvider);
    final catalog = ref.watch(catalogProvider);
    final isPro = ref.watch(proProvider).isPro;
    final foods = catalog.foodsByIds(draft.foodIds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your PlatePatch'),
        actions: [
          // Play requires in-app reporting wherever an AI-derived result is
          // shown, and this screen follows a scan.
          IconButton(
            tooltip: 'Report this result',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => ReportSheet.show(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
          children: [
            _PlateSummary(foods: foods),
            const SizedBox(height: Space.lg),
            Text(result.headline, style: Theme.of(context).textTheme.headlineMedium),
            if (result.gaps.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(
                result.gaps.first.benefit,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: PlateColors.inkSoft,
                    ),
              ),
            ],
            const SizedBox(height: Space.lg),
            if (result.isBalanced)
              const _BalancedNote()
            else if (result.patches.isEmpty)
              _NoSuggestions(isPro: isPro)
            else ...[
              for (final patch in result.patches) ...[
                _PatchCard(
                  patch: patch,
                  onAdd: () => _saveAndCheck(context, ref, result, patch),
                ),
                const SizedBox(height: Space.md),
              ],
            ],
            if (!isPro && result.patches.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              _ProNudge(
                onTap: () => PaywallScreen.show(context, reason: 'More ways to patch this meal'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndCheck(
    BuildContext context,
    WidgetRef ref,
    PatchResult result,
    Patch patch,
  ) async {
    final saved = SavedPatch(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      savedAt: DateTime.now(),
      slot: result.slot,
      foodIds: result.foods.map((f) => f.id).toList(),
      additionId: patch.addition.id,
      additionName: patch.addition.name,
      additionEmoji: patch.addition.emoji,
      gapIds: result.gaps.map((g) => g.id).toList(),
    );
    await ref.read(historyProvider.notifier).save(saved);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CheckScreen(patchId: saved.id)),
    );
    if (!context.mounted) return;
    // Back to a clean plate: the meal has been dealt with.
    ref.read(mealDraftProvider.notifier).reset();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _PlateSummary extends StatelessWidget {
  const _PlateSummary({required this.foods});

  final List<FoodItem> foods;

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🍽️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On your plate', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  foods.map((f) => '${f.emoji} ${f.name}').join('   '),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatchCard extends StatelessWidget {
  const _PatchCard({required this.patch, required this.onAdd});

  final Patch patch;
  final VoidCallback onAdd;

  static const _angleColors = {
    PickAngle.fastest: (PlateColors.amberSoft, PlateColors.clay),
    PickAngle.cheapest: (PlateColors.claySoft, PlateColors.clay),
    PickAngle.plantBased: (PlateColors.greenSoft, PlateColors.green),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _angleColors[patch.angle]!;
    return PlateCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pill(
            label: patch.angle.label,
            emoji: patch.angle.emoji,
            background: bg,
            foreground: fg,
          ),
          const SizedBox(height: Space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patch.addition.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  patch.addition.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(patch.addition.how, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: Space.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PlateColors.cream,
              borderRadius: BorderRadius.circular(kRadiusSmall),
            ),
            child: Text(
              patch.reason,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: onAdd,
            child: const Text("I'll add this"),
          ),
        ],
      ),
    );
  }
}

class _BalancedNote extends StatelessWidget {
  const _BalancedNote();

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      color: PlateColors.greenSoft,
      border: PlateColors.green,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👏', style: TextStyle(fontSize: 30)),
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
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🤷', style: TextStyle(fontSize: 30)),
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

class _ProNudge extends StatelessWidget {
  const _ProNudge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      onTap: onTap,
      color: PlateColors.amberSoft,
      border: PlateColors.amber,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const Text('✨', style: TextStyle(fontSize: 22)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PlatePatch Pro', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'The full ingredient library, unlimited saves, and your satisfaction history.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: PlateColors.inkSoft),
        ],
      ),
    );
  }
}
