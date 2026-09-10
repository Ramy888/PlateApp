import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/auth_providers.dart';
import '../theme.dart';
import 'common.dart';

/// Asked for at the moment it is needed, and not before.
///
/// The app opens to a guest and stays useful as one: pick a meal, build a plate
/// by hand, read what the rules engine works out on the phone. This appears the
/// first time someone reaches for something a model has to do, so the value is
/// already obvious by the time anything is asked of them.
class SignInSheet extends ConsumerStatefulWidget {
  const SignInSheet({super.key, this.reason});

  /// What they were trying to do. Named back to them, so the sheet reads as an
  /// answer rather than an interruption.
  final String? reason;

  @override
  ConsumerState<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<SignInSheet> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    // Google's own sheet takes over the screen while it works, and a stray
    // tap on what is left of ours used to close the whole thing underneath —
    // the sign-in then completed against a sheet that no longer existed, and
    // the person had to start again with no idea why. Locked while busy.
    return PopScope(
      canPop: !auth.busy,
      child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: Space.md),
                decoration: BoxDecoration(
                  color: PlateColors.neutral300,
                  borderRadius: BorderRadius.circular(kPill),
                ),
              ),
            ),
            if (widget.reason != null) ...[
              Pill(
                label: widget.reason!,
                background: PlateColors.greenSoft,
                foreground: PlateColors.green,
              ),
              const SizedBox(height: Space.md),
            ],
            Text('Sign in to use the AI', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: Space.sm),
            Text(
              'Reading photos, listening and drawing your plate all cost real '
              'money to run, so they need an account. Everything else stays '
              'free and signed out.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: PlateColors.inkSoft,
                  ),
            ),
            const SizedBox(height: Space.lg),
            const _Point(
              icon: LucideIcons.infinity,
              title: 'Three free to start',
              body: 'Three AI meals on the house, kept with your account rather '
                  'than this phone.',
            ),
            const _Point(
              icon: LucideIcons.lock,
              title: 'Your meals stay here',
              body: 'Saved meals and conversations stay on this phone. We keep '
                  'your name and email, and nothing about what you eat.',
            ),
            const _Point(
              icon: LucideIcons.trash2,
              title: 'Leave whenever',
              body: 'Delete my account is in Settings, and it removes the lot.',
            ),
            const SizedBox(height: Space.md),
            if (auth.problem != null) ...[
              PlateCard.pro(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.circleAlert, size: 18, color: PlateColors.pro),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(auth.problem!,
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
            ],
            FilledButton.icon(
              onPressed: auth.busy
                  ? null
                  : () async {
                      final ok = await ref.read(authControllerProvider.notifier).signIn();
                      if (ok && context.mounted) Navigator.of(context).pop(true);
                    },
              icon: auth.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PlateColors.neutral100,
                      ),
                    )
                  : const Icon(LucideIcons.logIn, size: 18),
              label: Text(auth.busy ? 'Signing in…' : 'Continue with Google'),
            ),
            const SizedBox(height: Space.xs),
            Center(
              child: TextButton(
                onPressed: auth.busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Lead(icon, size: 17),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The gate.
///
/// Called before the network request, not after it, so a guest never spends a
/// round trip to be told no. Returns true when there is an account to spend.
Future<bool> requireSignIn(
  BuildContext context,
  WidgetRef ref, {
  String? reason,
}) async {
  if (ref.read(authControllerProvider).isSignedIn) return true;

  final signedIn = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // A tap on the scrim, or a drag, must not cancel a sign-in that is
    // already in flight. The sheet closes itself when it is done, and "Not
    // now" is always there for anyone who genuinely wants out.
    isDismissible: false,
    enableDrag: false,
    backgroundColor: PlateColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
    ),
    builder: (_) => SignInSheet(reason: reason),
  );
  return signedIn ?? false;
}
