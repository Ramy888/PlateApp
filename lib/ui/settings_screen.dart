import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/prefs_repository.dart';
import '../domain/models.dart';
import '../state/auth_providers.dart';
import '../state/providers.dart';
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
            const _AccountHeader(),

            _Section(
              title: 'Your goal',
              note: 'Changes which suggestion comes first.',
              first: true,
              children: [
                for (final goal in Goal.values)
                  ChoiceRow(
                    flat: true,
                    icon: goal.icon,
                    title: goal.label,
                    subtitle: goal.blurb,
                    selected: settings.goal == goal,
                    onTap: () => ref.read(settingsProvider.notifier).setGoal(goal),
                  ),
              ],
            ),

            _Section(
              title: 'Leave out',
              note: 'Never suggested, in the app or by the AI.',
              children: [
                for (final pref in DietPref.values)
                  ChoiceRow(
                    flat: true,
                    icon: pref.icon,
                    title: pref.label,
                    subtitle: pref.blurb,
                    selected: settings.dietPrefs.contains(pref),
                    onTap: () => ref.read(settingsProvider.notifier).togglePref(pref),
                  ),
              ],
            ),

            _Section(
              title: 'Subscription',
              padded: true,
              children: [
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
              ],
            ),

            _Section(
              title: 'About',
              padded: true,
              children: [
                _LinkRow(
                    label: 'Privacy policy',
                    onTap: () => LegalScreen.showPrivacy(context)),
                const SizedBox(height: Space.sm),
                _LinkRow(
                    label: 'Terms of use', onTap: () => LegalScreen.showTerms(context)),
              ],
            ),

            const _Section(
              title: 'Your data',
              padded: true,
              children: [_DeleteMyData()],
            ),
            const SizedBox(height: Space.lg),
            const _VersionLine(),
          ],
        ),
      ),
    );
  }
}

/// A titled group inside one thin edge.
///
/// The page used to be a flat run of cards with headings floating between
/// them, and at seven headings it read as a list of unrelated things. One
/// hairline per group is enough to say where each one starts and stops, and it
/// lets the rows inside drop their own cards — a card inside a box is two
/// edges saying the same thing.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.note,
    this.first = false,
    this.padded = false,
  });

  final String title;
  final List<Widget> children;
  final String? note;
  final bool first;

  /// For groups whose contents are already cards of their own and need room
  /// to breathe inside the edge, rather than flat rows that fill it.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? Space.sm : Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(title),
          if (note != null) ...[
            Text(note!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: Space.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: PlateColors.line),
              borderRadius: BorderRadius.circular(kRadiusSmall),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadiusSmall - 1),
              child: Padding(
                padding: EdgeInsets.all(padded ? Space.md : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      // A hairline between flat rows, so the group reads as
                      // one object with parts rather than a stack of slabs.
                      if (i > 0 && !padded)
                        const Divider(height: 1, thickness: 1, color: PlateColors.line),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
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
/// Who this is, at the top of the page.
///
/// It used to be the fourth section down, in a row like any other setting.
/// Whose account this is answers a different question from what the app should
/// suggest, and it answers it before any of the others are worth reading — so
/// it sits above them, centred, with a face on it.
class _AccountHeader extends ConsumerWidget {
  const _AccountHeader();

  /// Asks first.
  ///
  /// Signing out is not deleting — the account and its remaining free tries
  /// survive it — but it does end the session on this phone, and the button
  /// sits one tap from the avatar. The dialog also says what signing out is
  /// *not*, because that is the thing people actually worry about here.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PlateColors.card,
        title: const Text('Sign out?'),
        content: const Text(
          'Scanning, chat, voice and drawn plates will ask for an account '
          'again.\n\n'
          'Nothing is deleted. Your saved patches stay on this phone, and your '
          'account keeps whatever free tries it has left for when you come '
          'back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final text = Theme.of(context).textTheme;

    if (!auth.isSignedIn) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xs),
        child: Column(
          children: [
            const _Avatar(url: null, name: '', size: 84),
            const SizedBox(height: Space.md),
            Text('Not signed in', style: text.titleLarge),
            const SizedBox(height: 2),
            Text(
              'Sign in to scan, chat, speak, or have a plate drawn.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton(
              onPressed: () => requireSignIn(context, ref),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xs),
      child: Column(
        children: [
          _Avatar(url: auth.photoUrl, name: auth.shortName, size: 84),
          const SizedBox(height: Space.md),
          Text(
            auth.user!.name.isEmpty ? auth.shortName : auth.user!.name,
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(auth.user!.email, style: text.bodyMedium),
          const SizedBox(height: Space.xs),
          // Quiet, because signing out is a thing you look for rather than a
          // thing you should be offered.
          TextButton(
            onPressed: () => _confirmSignOut(context, ref),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Google's avatar, with the initial as the fallback. The URL is read from the
/// session and never sent to our server — it is Google's to serve.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, this.size = 44});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: PlateColors.greenSoft,
      ),
      child: url == null
          ? _fallback()
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Google's own URL, and it can fail like any other: no network,
              // a revoked photo, a rate limit. The page must still show who is
              // signed in.
              errorBuilder: (context, _, _) => _fallback(),
            ),
    );
  }

  /// An initial when there is a name to take one from, and a person otherwise —
  /// a lone "?" on the signed-out page reads as an error rather than an
  /// invitation.
  Widget _fallback() {
    if (name.isEmpty) {
      return Icon(LucideIcons.user, size: size * 0.46, color: PlateColors.green);
    }
    return Text(
      name.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: size * 0.41,
        fontWeight: FontWeight.w700,
        color: PlateColors.green,
      ),
    );
  }
}
