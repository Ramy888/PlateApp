import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prefs_repository.dart';
import '../domain/models.dart';
import '../state/providers.dart';
import 'check_screen.dart';
import 'paywall_screen.dart';
import 'icons.g.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Saved patches, plus the satisfaction history that Pro unlocks.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleHistoryProvider);
    final locked = ref.watch(lockedHistoryCountProvider);
    final isPro = ref.watch(proProvider).isPro;
    final all = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved patches'),
        actions: [
          if (!isPro)
            TextButton(
              onPressed: () => PaywallScreen.show(context, reason: 'Unlimited saved meals'),
              child: const Text('Get Pro'),
            ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: visible.isEmpty
            ? const EmptyState(
                icon: LucideIcons.bookmark,
                title: 'Nothing saved yet',
                message: 'Patch a meal and tap "I\'ll add this" — it will show up here.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
                children: [
                  if (isPro && all.any((h) => h.satisfaction != null)) ...[
                    _SatisfactionSummary(history: all),
                    const SizedBox(height: Space.lg),
                  ],
                  for (final patch in visible) ...[
                    _SavedRow(
                      patch: patch,
                      onCheck: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CheckScreen(patchId: patch.id),
                        ),
                      ),
                      onRemove: () => ref.read(historyProvider.notifier).remove(patch.id),
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                  if (locked > 0) ...[
                    const SizedBox(height: Space.sm),
                    _LockedNote(count: locked),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SavedRow extends ConsumerWidget {
  const _SavedRow({required this.patch, required this.onCheck, required this.onRemove});

  final SavedPatch patch;
  final VoidCallback onCheck;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Saved rows persist an id, not an icon — rows written before the app used
    // icons carry only an emoji, and renaming that key would blank the history
    // of every existing install. The glyph is looked up from the id instead.
    final addition = ref
        .watch(catalogProvider)
        .additions
        .where((a) => a.id == patch.additionId);
    final icon = catalogIcon(addition.isEmpty ? null : addition.first.icon);

    return PlateCard(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlateThumb(icon, small: true),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patch.additionName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${patch.slot.label} · ${_relative(patch.savedAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.sm),
                if (patch.satisfaction != null)
                  Pill(
                    label: patch.satisfaction!.label,
                    icon: patch.satisfaction!.icon,
                    background: PlateColors.neutral200,
                    foreground: PlateColors.inkSoft,
                  )
                else
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onCheck,
                    child: const Text('How did it go?'),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(LucideIcons.x, size: 18, color: PlateColors.inkSoft),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return '${when.day}/${when.month}';
  }
}

/// Pro-only: the pattern across recent after-meal checks, in words.
class _SatisfactionSummary extends StatelessWidget {
  const _SatisfactionSummary({required this.history});

  final List<SavedPatch> history;

  @override
  Widget build(BuildContext context) {
    final checked = history.where((h) => h.satisfaction != null).toList();
    final comfortable =
        checked.where((h) => h.satisfaction == Satisfaction.comfortable).length;

    return PlateCard(
      color: PlateColors.greenSoft,
      border: PlateColors.green,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your satisfaction history',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'You felt comfortably satisfied after $comfortable of your last '
            '${checked.length} patched meals.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              for (final s in Satisfaction.values) ...[
                Expanded(
                  child: _Tally(
                    icon: s.icon,
                    label: s.label,
                    count: checked.where((h) => h.satisfaction == s).length,
                  ),
                ),
                if (s != Satisfaction.values.last) const SizedBox(width: Space.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.icon, required this.label, required this.count});

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xs),
      decoration: BoxDecoration(
        color: PlateColors.neutral100,
        borderRadius: BorderRadius.circular(kRadiusSmall),
      ),
      child: Column(
        children: [
          Icon(icon, size: 17, color: PlateColors.green),
          const SizedBox(height: 4),
          Text('$count',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, height: 1.2, color: PlateColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _LockedNote extends StatelessWidget {
  const _LockedNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      onTap: () => PaywallScreen.show(context, reason: 'Unlimited saved meals'),
      color: PlateColors.warnSoft,
      border: PlateColors.warn,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const Icon(LucideIcons.lock, color: PlateColors.pro),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1 ? '1 more saved patch' : '$count more saved patches',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Free keeps your ${PrefsRepository.freeSavedLimit} most recent. '
                  'The rest are still on your device — Pro brings them back.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
