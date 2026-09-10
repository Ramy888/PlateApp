import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/prefs_repository.dart';
import '../domain/models.dart';
import '../state/auth_providers.dart';
import '../state/providers.dart';
import '../data/scan_api.dart';
import '../state/scan_providers.dart';
import 'legal_screen.dart';
import 'paywall_screen.dart';
import 'theme.dart';
import 'widgets/sign_in_sheet.dart';
import 'widgets/common.dart';

/// Everything chosen during onboarding, changeable afterwards.
///
/// Without this screen a goal picked in the first thirty seconds of using the
/// app was permanent, which is the kind of gap that only shows up when someone
/// tries to change their mind.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});



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
                icon: goal.icon,
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
                icon: pref.icon,
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

            const _SectionHeading('Account'),
            const _AccountCard(),

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
      // .pp-heading in the design: the body face at 16/700, not the display
      // face. Caprasimo is reserved for .pp-h2 — empty states, dialogs,
      // addition names and legal section heads.
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
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
          Lead(isPro ? LucideIcons.sparkles : LucideIcons.utensils),
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
          const Icon(LucideIcons.chevronRight, color: PlateColors.inkSoft),
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
      return 'You have used your three free AI meals. Building meals by hand '
          'is still free.';
    }
    // Counted in tries rather than days: the allowance is three generations
    // for the life of the account, and a clock would be a different promise.
    final tries = quota.triesLeft;
    return tries == 1 ? '1 free AI meal left' : '$tries free AI meals left';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(scanControllerProvider).quota;
    return PlateCard(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const Lead(LucideIcons.camera),
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
        title: const Text('Delete my account and data'),
        content: const Text(
          'This removes your saved patches, their pictures, your conversations '
          'and your preferences from this phone, and tells our server to forget '
          'your account — your name, your email, your allowance, and every '
          'record of a scan.\n\n'
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
              'Delete my account and data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: PlateColors.pro,
                  ),
            ),
          ),
          const Icon(LucideIcons.chevronRight, color: PlateColors.inkSoft),
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


/// Who is signed in, and the two things a person is entitled to do about it.
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    if (!auth.isSignedIn) {
      return PlateCard(
        onTap: () => requireSignIn(context, ref),
        child: Row(
          children: [
            const Lead(LucideIcons.logIn),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Not signed in', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Sign in to scan, chat, speak, or have a plate drawn.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: PlateColors.inkSoft),
          ],
        ),
      );
    }

    return Column(
      children: [
        PlateCard(
          child: Row(
            children: [
              _Avatar(url: auth.photoUrl, name: auth.shortName),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user!.name.isEmpty ? auth.shortName : auth.user!.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(auth.user!.email,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        PlateCard(
          onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          child: Row(
            children: [
              Text('Sign out', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              const Icon(LucideIcons.chevronRight, color: PlateColors.inkSoft),
            ],
          ),
        ),
      ],
    );
  }
}

/// Google's avatar, with the initial as the fallback. The URL is read from the
/// session and never sent to our server — it is Google's to serve.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: PlateColors.greenSoft),
      child: url == null
          ? Text(initial,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: PlateColors.green,
              ))
          : Image.network(
              url!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => Text(initial,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: PlateColors.green,
                  )),
            ),
    );
  }
}
