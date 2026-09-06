import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'paywall_screen.dart';
import 'result_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// "What are you eating?" — the only input screen in the app.
class MealScreen extends ConsumerWidget {
  const MealScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(mealDraftProvider);
    final catalog = ref.watch(catalogProvider);
    final isPro = ref.watch(proProvider).isPro;
    final foods = catalog.foodsForSlot(draft.slot);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlatePatch'),
        actions: [
          IconButton(
            tooltip: 'Saved patches',
            icon: const Icon(Icons.bookmark_border),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SavedScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
                children: [
                  Text('What are you eating?',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Tap everything on the plate. Rough is fine.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Space.md),
                  _SlotSelector(
                    selected: draft.slot,
                    onSelect: (s) => ref.read(mealDraftProvider.notifier).setSlot(s),
                  ),
                  const SizedBox(height: Space.lg),
                  _FoodGrid(
                    foods: foods,
                    selected: draft.foodIds,
                    isPro: isPro,
                    onToggle: (f) {
                      if (!f.isFree && !isPro) {
                        PaywallScreen.show(context, reason: '${f.name} is part of Pro');
                        return;
                      }
                      ref.read(mealDraftProvider.notifier).toggleFood(f.id);
                    },
                  ),
                ],
              ),
            ),
            _PatchBar(
              count: draft.foodIds.length,
              onPressed: draft.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const ResultScreen()),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotSelector extends StatelessWidget {
  const _SlotSelector({required this.selected, required this.onSelect});

  final MealSlot selected;
  final ValueChanged<MealSlot> onSelect;

  static const _emoji = {
    MealSlot.breakfast: '🌅',
    MealSlot.lunchDinner: '🍽️',
    MealSlot.snack: '🍪',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final slot in MealSlot.values) ...[
          Expanded(
            child: _SlotChip(
              emoji: _emoji[slot]!,
              label: slot == MealSlot.lunchDinner ? 'Lunch\nor dinner' : slot.label,
              selected: slot == selected,
              onTap: () => onSelect(slot),
            ),
          ),
          if (slot != MealSlot.values.last) const SizedBox(width: Space.sm),
        ],
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: PlateCard(
        onTap: onTap,
        color: selected ? PlateColors.green : PlateColors.card,
        border: selected ? PlateColors.green : null,
        padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.sm),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : PlateColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodGrid extends StatelessWidget {
  const _FoodGrid({
    required this.foods,
    required this.selected,
    required this.isPro,
    required this.onToggle,
  });

  final List<FoodItem> foods;
  final Set<String> selected;
  final bool isPro;
  final ValueChanged<FoodItem> onToggle;

  @override
  Widget build(BuildContext context) {
    final free = foods.where((f) => f.isFree).toList();
    final locked = foods.where((f) => !f.isFree).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Grid(foods: free, selected: selected, locked: false, onToggle: onToggle),
        if (locked.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Text('More foods', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: Space.sm),
              if (!isPro) const Pill(label: 'PRO', emoji: '✨',
                  background: PlateColors.amberSoft, foreground: PlateColors.clay),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            isPro
                ? 'Egyptian, MENA and international dishes.'
                : 'Egyptian, MENA and international dishes, in Pro.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.md),
          _Grid(foods: locked, selected: selected, locked: !isPro, onToggle: onToggle),
        ],
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.foods,
    required this.selected,
    required this.locked,
    required this.onToggle,
  });

  final List<FoodItem> foods;
  final Set<String> selected;
  final bool locked;
  final ValueChanged<FoodItem> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final food in foods)
          _FoodTile(
            food: food,
            selected: selected.contains(food.id),
            locked: locked,
            onTap: () => onToggle(food),
          ),
      ],
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({
    required this.food,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final FoodItem food;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(kRadiusSmall);
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '${food.name}, locked, Pro' : food.name,
      child: Material(
        color: selected ? PlateColors.greenSoft : PlateColors.card,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(
                color: selected ? PlateColors.green : PlateColors.line,
                width: 1.5,
              ),
            ),
            child: Opacity(
              opacity: locked ? 0.55 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(food.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    food.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: PlateColors.ink,
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.lock_outline, size: 14, color: PlateColors.inkSoft),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sticky footer. Disabled until something is on the plate, because a patch
/// with no meal to patch is meaningless.
class _PatchBar extends StatelessWidget {
  const _PatchBar({required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      decoration: const BoxDecoration(
        color: PlateColors.cream,
        border: Border(top: BorderSide(color: PlateColors.line)),
      ),
      child: FilledButton(
        onPressed: onPressed,
        child: Text(count == 0
            ? 'Pick what you are eating'
            : 'Patch this meal  ·  $count selected'),
      ),
    );
  }
}
