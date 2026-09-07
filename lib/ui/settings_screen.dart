import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/prefs_repository.dart';
import '../domain/models.dart';
import '../state/providers.dart';
import '../data/scan_api.dart';
import '../state/scan_providers.dart';
import 'legal_screen.dart';
import 'paywall_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Everything chosen during onboarding, changeable afterwards.
///
/// Without this screen a goal picked in the first thirty seconds of using the
/// app was permanent, which is the kind of gap that only shows up when someone
/// tries to change their mind.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _goalEmoji = {
    Goal.feelSatisfied: '😌',
    Goal.moreEnergy: '⚡',
    Goal.betterMeals: '🍽️',
  };

  static const _prefEmoji = {
    DietPref.vegetarian: '🥬',
    DietPref.dairyFree: '🥛',
    DietPref.lowCost: '💰',
    DietPref.glutenFree: '🌾',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final pro = ref.watch(proProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
          children: [
            const _SectionHeading('Your goal', first: true),
            Text(
              'Changes which suggestion comes first.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.md),
            for (final goal in Goal.values) ...[
              ChoiceRow(
                emoji: _goalEmoji[goal]!,
                title: goal.label,
                subtitle: goal.blurb,
                selected: settings.goal == goal,
                onTap: () => ref.read(settingsProvider.notifier).setGoal(goal),
              ),
              const SizedBox(height: Space.sm),
            ],

            const _SectionHeading('Leave out'),
            Text(
              'Suggestions will never include these.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.md),
            for (final pref in DietPref.values) ...[
              ChoiceRow(
                emoji: _prefEmoji[pref]!,
                title: pref.label,
                subtitle: pref.blurb,
                selected: settings.dietPrefs.contains(pref),
                onTap: () => ref.read(settingsProvider.notifier).togglePref(pref),
              ),
              const SizedBox(height: Space.sm),
            ],

            const _SectionHeading('Subscription'),
            _ProStatusCard(isPro: pro.isPro),
            const SizedBox(height: Space.sm),
            _LinkRow(
              label: 'Restore purchases',
              onTap: () async {
                await ref.read(proProvider.notifier).restore();
                if (!context.mounted) return;
                final message = ref.read(proProvider).message;
                if (message == null) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(message)));
                ref.read(proProvider.notifier).clearMessage();
              },
            ),

            const _SectionHeading('About'),
            _LinkRow(label: 'Privacy policy', onTap: () => LegalScreen.showPrivacy(context)),
            const SizedBox(height: Space.sm),
            _LinkRow(label: 'Terms of use', onTap: () => LegalScreen.showTerms(context)),
            const _SectionHeading('Your data'),
            const _ScanAllowance(),
            const SizedBox(height: Space.sm),
            const _DeleteMyData(),
            const SizedBox(height: Space.lg),
            const _VersionLine(),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text, {this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? Space.sm : Space.xl, bottom: Space.xs),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ProStatusCard extends StatelessWidget {
  const _ProStatusCard({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      color: isPro ? PlateColors.greenSoft : PlateColors.card,
      border: isPro ? PlateColors.green : null,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          Text(isPro ? '✨' : '🍽️', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isPro ? 'Plate Pro' : 'Free plan',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  isPro
                      ? 'Everything unlocked.'
                      : '${PrefsRepository.freeSavedLimit} saved patches · common foods',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (!isPro)
            TextButton(
              onPressed: () => PaywallScreen.show(context, reason: 'Everything in Pro'),
              child: const Text('See Pro'),
            ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          const Icon(Icons.chevron_right, color: PlateColors.inkSoft),
        ],
      ),
    );
  }
}

/// What the scan allowance is, without spending one to find out.
class _ScanAllowance extends ConsumerWidget {
  const _ScanAllowance();

  static String _describe(ScanQuota? quota) {
    if (quota == null) return 'Scan a meal to see how many you have left.';
    if (quota.pro) return '${quota.scans} left this month';
    if (!quota.trialActive) {
      return 'Your free week has ended. Building meals by hand is still free.';
    }
    final days = quota.trialDaysLeft == 1 ? 'Last day' : '${quota.trialDaysLeft} days left';
    return '${quota.scans} left today · $days of your free week';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(scanControllerProvider).quota;
    return PlateCard(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const Text('📸', style: TextStyle(fontSize: 22)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI meal scans', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(_describe(quota), style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Backs the promise made in the privacy policy and on the deletion page.
///
/// Deliberately understated: clay rather than red, and no warning triangle.
/// It is a legitimate thing to want, not a mistake to be talked out of.
class _DeleteMyData extends ConsumerWidget {
  const _DeleteMyData();

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PlateColors.card,
        title: const Text('Delete my data'),
        content: const Text(
          'This removes your saved patches and preferences from this phone, and '
          'tells our server to forget this device and its scan allowance.\n\n'
          'It cannot be undone, and it does not cancel a subscription.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: PlateColors.pro),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await ref.read(scanControllerProvider.notifier).deleteEverything();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Your data has been deleted.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlateCard(
      onTap: () => _confirm(context, ref),
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Delete my data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: PlateColors.pro,
                  ),
            ),
          ),
          const Icon(Icons.chevron_right, color: PlateColors.inkSoft),
        ],
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        // No placeholder while it loads: a version number flickering in is
        // noisier than one that simply appears.
        final label = info == null ? '' : 'The Plate ${info.version} (${info.buildNumber})';
        return Center(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        );
      },
    );
  }
}
