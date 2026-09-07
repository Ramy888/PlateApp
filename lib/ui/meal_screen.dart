import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'icons.g.dart';
import 'paywall_screen.dart';
import 'result_screen.dart';
import 'scan_camera_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// "What are you eating?" — the only input screen in the app.
///
/// The meal comes first, and only then the food, one collapsible rail per kind
/// of thing. Scanning floats over all of it as the one shortcut out, because a
/// photo answers the whole screen in a single tap.
class MealScreen extends ConsumerStatefulWidget {
  const MealScreen({super.key});

  @override
  ConsumerState<MealScreen> createState() => _MealScreenState();
}

class _MealScreenState extends ConsumerState<MealScreen> {
  /// Which rail is open. Null means the first one; `_noneOpen` means the user
  /// closed it and wants them all shut.
  String? _openRail;
  static const _noneOpen = '__none';

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(mealDraftProvider);
    final catalog = ref.watch(catalogProvider);
    final isPro = ref.watch(proProvider).isPro;
    final rails = _rails(catalog.foodsForSlot(draft.slot), isPro);

    final openId = _openRail == _noneOpen
        ? null
        : (rails.any((r) => r.group.id == _openRail)
            ? _openRail
            : (rails.isEmpty ? null : rails.first.group.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('The Plate'),
        actions: [
          IconButton(
            tooltip: 'Saved patches',
            icon: const Icon(LucideIcons.bookmark),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SavedScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(LucideIcons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: _ScanFab(slot: draft.slot),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 96),
                children: [
                  Text('What are you eating?',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Pick the meal, then tap what is on the plate. Rough is fine.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Space.md),
                  _SlotSelector(
                    selected: draft.slotChosen ? draft.slot : null,
                    onSelect: (s) {
                      setState(() => _openRail = null);
                      ref.read(mealDraftProvider.notifier).setSlot(s);
                    },
                  ),
                  const SizedBox(height: Space.md),
                  if (!draft.slotChosen)
                    const Inset(
                      icon: LucideIcons.arrowUp,
                      child: Text(
                        'Pick a meal above to see what can go on the plate — '
                        'or scan it instead.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: PlateColors.inkSoft,
                        ),
                      ),
                    )
                  else
                    for (final rail in rails) ...[
                      _Rail(
                        rail: rail,
                        open: openId == rail.group.id,
                        chosen: rail.foods.where((f) => draft.foodIds.contains(f.id)).length,
                        showProTag: rail.locked && !isPro,
                        selectedIds: draft.foodIds,
                        isPro: isPro,
                        onToggleOpen: () => setState(
                          () => _openRail = openId == rail.group.id ? _noneOpen : rail.group.id,
                        ),
                        onTapFood: (f) {
                          if (!f.isFree && !isPro) {
                            PaywallScreen.show(context, reason: '${f.name} is part of Pro');
                            return;
                          }
                          ref.read(mealDraftProvider.notifier).toggleFood(f.id);
                        },
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                ],
              ),
            ),
            _PatchBar(
              count: draft.foodIds.length,
              slotChosen: draft.slotChosen,
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

/// One rail's worth of food: a group, or the single locked rail that stands in
/// for every Pro collection at once.
class _RailData {
  const _RailData(this.group, this.foods, {this.locked = false});

  final FoodGroup group;
  final List<FoodItem> foods;
  final bool locked;
}

List<_RailData> _rails(List<FoodItem> foods, bool isPro) {
  final rails = <_RailData>[];
  for (final group in FoodGroup.all) {
    final items = foods
        .where((f) => (isPro || f.isFree) && f.group == group.id)
        .toList(growable: false);
    if (items.isNotEmpty) rails.add(_RailData(group, items));
  }
  if (!isPro) {
    // Every locked collection collapses into one rail. Showing them is what
    // sells Pro; showing them scattered through eight rails just reads as
    // eight things that do not work.
    final locked = foods.where((f) => !f.isFree).toList(growable: false);
    if (locked.isNotEmpty) {
      rails.add(_RailData(FoodGroup.locked, locked, locked: true));
    }
  }
  return rails;
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.rail,
    required this.open,
    required this.chosen,
    required this.showProTag,
    required this.selectedIds,
    required this.isPro,
    required this.onToggleOpen,
    required this.onTapFood,
  });

  final _RailData rail;
  final bool open;
  final int chosen;
  final bool showProTag;
  final Set<String> selectedIds;
  final bool isPro;
  final VoidCallback onToggleOpen;
  final ValueChanged<FoodItem> onTapFood;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(kPill);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: Material(
            color: open ? PlateColors.greenSoft : PlateColors.card,
            borderRadius: shape,
            child: InkWell(
              onTap: onToggleOpen,
              borderRadius: shape,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(rail.group.icon, size: 18, color: PlateColors.green),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        rail.group.label,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (showProTag) ...[
                      const Pill(
                        label: 'PRO',
                        icon: LucideIcons.sparkles,
                        background: PlateColors.proSoft,
                        foreground: PlateColors.pro,
                      ),
                      const SizedBox(width: Space.sm),
                    ],
                    if (chosen > 0) ...[
                      _Count(chosen),
                      const SizedBox(width: Space.sm),
                    ],
                    Icon(
                      open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 19,
                      color: PlateColors.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                // The rail bleeds to the screen edge, so a half-visible tile
                // says "there is more" without a scrollbar saying it.
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                itemCount: rail.foods.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
                itemBuilder: (_, i) {
                  final food = rail.foods[i];
                  return FoodTile(
                    icon: catalogIcon(food.icon),
                    label: food.name,
                    selected: selectedIds.contains(food.id),
                    locked: !food.isFree && !isPro,
                    onTap: () => onTapFood(food),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: PlateColors.green,
        borderRadius: BorderRadius.circular(kPill),
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: PlateColors.neutral100,
        ),
      ),
    );
  }
}

/// The scan shortcut. A floating action rather than a card, so it stays
/// reachable however far down the rails you have scrolled.
class _ScanFab extends StatelessWidget {
  const _ScanFab({required this.slot});

  final MealSlot slot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Clear of the sticky footer beneath it.
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ScanCameraScreen(slot: slot)),
        ),
        backgroundColor: PlateColors.green,
        foregroundColor: PlateColors.neutral100,
        icon: const Icon(LucideIcons.camera, size: 22),
        label: const Text(
          'Scan my meal',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SlotSelector extends StatelessWidget {
  const _SlotSelector({required this.selected, required this.onSelect});

  /// Null until the user has picked one.
  final MealSlot? selected;
  final ValueChanged<MealSlot> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slot in MealSlot.values) ...[
          Expanded(
            child: _SlotTile(
              icon: slot.icon,
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

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(kRadiusSmall);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? PlateColors.green : PlateColors.card,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? PlateColors.neutral100.withValues(alpha: 0.18)
                        : PlateColors.neutral100,
                    borderRadius: BorderRadius.circular(kRadius * 0.7),
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: selected ? PlateColors.neutral100 : PlateColors.green,
                  ),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: selected ? PlateColors.neutral100 : PlateColors.ink,
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

/// Sticky footer. Disabled until something is on the plate, because a patch
/// with no meal to patch is meaningless. The label says which of the two
/// missing things is missing.
class _PatchBar extends StatelessWidget {
  const _PatchBar({
    required this.count,
    required this.slotChosen,
    required this.onPressed,
  });

  final int count;
  final bool slotChosen;
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
        child: Text(
          count == 0
              ? (slotChosen ? 'Pick what you are eating' : 'Pick a meal to start')
              : 'Patch this meal · $count selected',
        ),
      ),
    );
  }
}
