import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/prefs_repository.dart';
import '../data/purchases_service.dart';
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
                _ProStatusCard(
                  pro: pro,
                  signedIn: ref.watch(authControllerProvider).isSignedIn,
                ),
                const SizedBox(height: Space.sm),
                _LinkRow(
                  label: 'Restore purchases',
                  onTap: () async {
                    if (!await _confirmRestore(context)) return;
                    if (!context.mounted) return;
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

/// What the plan line says under "Plate Pro".
///
/// Names the plan rather than repeating "everything unlocked", because the one
/// thing a subscriber cannot see anywhere else in the app is which plan they
/// are actually paying for — and, during the introductory period, that they
/// have not been charged yet.
String _planLine(ProStatus pro, {required bool signedIn}) {
  // Every paid feature needs an account, so a subscription with nobody signed
  // in unlocks precisely nothing. Saying "everything unlocked" over a page
  // headed "Not signed in" is the app contradicting itself on one screen.
  if (!signedIn) return 'Sign in to use your subscription';

  final plan = switch (pro.plan) {
    ProPlan.monthly => 'Monthly plan',
    ProPlan.yearly => 'Yearly plan',
    ProPlan.none => 'Everything unlocked',
  };
  return pro.inTrial ? '$plan · free trial' : '$plan · everything unlocked';
}

class _ProStatusCard extends ConsumerWidget {
  const _ProStatusCard({required this.pro, required this.signedIn});

  final ProStatus pro;
  final bool signedIn;

  bool get isPro => pro.isPro;

  /// Pro, and able to use it. The celebratory treatment is reserved for this:
  /// a subscription that cannot currently do anything should not be dressed as
  /// a reward.
  bool get isUsable => pro.isPro && signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlateCard(
      color: isUsable ? PlateColors.greenSoft : PlateColors.card,
      border: isUsable ? PlateColors.green : null,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          Lead(isUsable ? LucideIcons.sparkles : LucideIcons.utensils),
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
                      ? _planLine(pro, signedIn: signedIn)
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
            )
          // Only a monthly subscriber is shown this. Offering an upgrade to
          // someone already on the yearly plan is the kind of prompt that makes
          // a person check whether they are being charged twice.
          // Not while signed out: selling an upgrade to a subscription that
          // currently does nothing is the wrong order of business.
          else if (isUsable && pro.canUpgradeToYearly)
            TextButton(
              // In the app now, not a link out to the Play website. The store
              // is told which subscription is being replaced, so this is a
              // change of plan rather than a second purchase — without that it
              // becomes two subscriptions and two charges.
              onPressed: pro.purchasing ? null : () => _confirmYearly(context, ref),
              child: Text(pro.purchasing ? 'Switching…' : 'Go yearly'),
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

/// Asks before restoring.
///
/// Restoring is not destructive, but it does talk to the store and can change
/// which account the subscription is attached to — so it is the kind of thing
/// that should happen because someone meant it, not because they were scrolling
/// settings and their thumb landed on a row.
///
/// It also sets an expectation: the answer may be "nothing to restore", and
/// being told that after choosing it reads very differently from being told it
/// after an accidental tap.
Future<bool> _confirmRestore(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: PlateColors.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
      title: Text('Restore purchases?',
          style: Theme.of(dialogContext).textTheme.titleLarge),
      content: Text(
        'This checks the store for a subscription bought with this account and '
        'puts it back on this phone.',
        style: Theme.of(dialogContext).textTheme.bodyLarge,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// Asks before changing plan, and says what changing means.
///
/// A subscription change bills immediately, and someone who taps "Go yearly"
/// expecting a page of information should not find they have been charged for
/// a year. The credit for the unused month is the part worth stating: it is
/// what makes this an upgrade rather than a second purchase.
Future<void> _confirmYearly(BuildContext context, WidgetRef ref) async {
  final pro = ref.read(proProvider);
  final price = pro.annual?.storeProduct.priceString ?? 'the yearly price';

  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: PlateColors.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
      title: Text('Switch to yearly?', style: Theme.of(dialogContext).textTheme.titleLarge),
      content: Text(
        'You will be charged $price now, and whatever is left of this month '
        'is credited against it. Your monthly plan stops.',
        style: Theme.of(dialogContext).textTheme.bodyLarge,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Switch'),
        ),
      ],
    ),
  );
  if (!(yes ?? false) || !context.mounted) return;

  await ref.read(proProvider.notifier).upgradeToYearly();
  if (!context.mounted) return;
  final message = ref.read(proProvider).message;
  if (message == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  ref.read(proProvider.notifier).clearMessage();
}
