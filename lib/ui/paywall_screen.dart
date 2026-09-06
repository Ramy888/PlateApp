import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:url_launcher/url_launcher.dart';

import '../data/purchases_service.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// The one paywall. Reachable from a locked food, a locked save, or the nudge
/// on the result screen — always with the reason that brought the user here.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.reason});

  final String? reason;

  static const privacyPolicyUrl = 'https://platepatch.app/privacy';
  static const termsUrl = 'https://platepatch.app/terms';

  static Future<void> show(BuildContext context, {String? reason}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaywallScreen(reason: reason),
          fullscreenDialog: true,
        ),
      );

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Package? _selected;

  static const _benefits = [
    ('📚', 'The full ingredient library', 'Every addition, not just the common ones.'),
    ('🌍', 'Egyptian, MENA and world foods', 'Koshari, fuul, molokhia, sushi, tacos and more.'),
    ('♾️', 'Unlimited saved patches', 'Keep every meal you have patched, not just three.'),
    ('📈', 'Your satisfaction history', 'See which additions actually kept you full.'),
    ('🎛️', 'Dietary and budget filters', 'Vegetarian, dairy-free, gluten-free and low cost.'),
  ];

  @override
  Widget build(BuildContext context) {
    final pro = ref.watch(proProvider);
    final selected = _selected ?? pro.annual ?? pro.monthly;

    ref.listen<ProStatus>(proProvider, (previous, next) {
      final message = next.message;
      if (message == null || message == previous?.message) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      ref.read(proProvider.notifier).clearMessage();
      if (next.isPro && mounted) Navigator.of(context).maybePop();
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                children: [
                  if (widget.reason != null) ...[
                    Pill(
                      label: widget.reason!,
                      background: PlateColors.amberSoft,
                      foreground: PlateColors.clay,
                    ),
                    const SizedBox(height: Space.md),
                  ],
                  Text('PlatePatch Pro',
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: Space.sm),
                  Text(
                    'Same simple idea, a much bigger pantry behind it.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: PlateColors.inkSoft,
                        ),
                  ),
                  const SizedBox(height: Space.lg),
                  for (final (emoji, title, body) in _benefits) ...[
                    _Benefit(emoji: emoji, title: title, body: body),
                    const SizedBox(height: Space.md),
                  ],
                  const SizedBox(height: Space.sm),
                  if (pro.isPro)
                    const _AlreadyPro()
                  else if (pro.hasProducts)
                    _PlanChoices(
                      pro: pro,
                      selected: selected,
                      onSelect: (p) => setState(() => _selected = p),
                    )
                  else
                    const _StoreUnavailable(),
                ],
              ),
            ),
            _Footer(
              pro: pro,
              selected: selected,
              onBuy: selected == null
                  ? null
                  : () => ref.read(proProvider.notifier).buy(selected),
              onRestore: () => ref.read(proProvider.notifier).restore(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.emoji, required this.title, required this.body});

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
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
    );
  }
}

class _PlanChoices extends StatelessWidget {
  const _PlanChoices({required this.pro, required this.selected, required this.onSelect});

  final ProStatus pro;
  final Package? selected;
  final ValueChanged<Package> onSelect;

  @override
  Widget build(BuildContext context) {
    final annual = pro.annual;
    final monthly = pro.monthly;

    return Column(
      children: [
        if (annual != null) ...[
          _PlanCard(
            package: annual,
            title: 'Yearly',
            // The trial is configured on the Play base plan, not in code, so
            // only advertise it when the store actually reports one.
            highlight: _introOffer(annual) ?? 'Best value',
            selected: identical(selected, annual),
            onTap: () => onSelect(annual),
          ),
          const SizedBox(height: Space.sm),
        ],
        if (monthly != null)
          _PlanCard(
            package: monthly,
            title: 'Monthly',
            highlight: _introOffer(monthly),
            selected: identical(selected, monthly),
            onTap: () => onSelect(monthly),
          ),
      ],
    );
  }

  static String? _introOffer(Package package) {
    final period = package.storeProduct.introductoryPrice?.periodNumberOfUnits;
    if (period == null || period <= 0) return null;
    return '$period-day free trial';
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.package,
    required this.title,
    required this.selected,
    required this.onTap,
    this.highlight,
  });

  final Package package;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      onTap: onTap,
      color: selected ? PlateColors.greenSoft : PlateColors.card,
      border: selected ? PlateColors.green : null,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (highlight != null) ...[
                      const SizedBox(width: Space.sm),
                      Pill(
                        label: highlight!,
                        background: PlateColors.amberSoft,
                        foreground: PlateColors.clay,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  package.storeProduct.priceString,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? PlateColors.green : PlateColors.line,
          ),
        ],
      ),
    );
  }
}

class _AlreadyPro extends StatelessWidget {
  const _AlreadyPro();

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      color: PlateColors.greenSoft,
      border: PlateColors.green,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const Text('✨', style: TextStyle(fontSize: 22)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'You are on PlatePatch Pro. Everything is unlocked.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the store has no products to sell: offline, a build without an
/// API key, or a device without Play billing. Restore stays available.
class _StoreUnavailable extends StatelessWidget {
  const _StoreUnavailable();

  @override
  Widget build(BuildContext context) {
    return PlateCard(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pro is not available right now',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'The store could not be reached. Check your connection and try again — '
            'everything free in PlatePatch keeps working either way.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.pro,
    required this.selected,
    required this.onBuy,
    required this.onRestore,
  });

  final ProStatus pro;
  final Package? selected;
  final VoidCallback? onBuy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      decoration: const BoxDecoration(
        color: PlateColors.cream,
        border: Border(top: BorderSide(color: PlateColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!pro.isPro)
            FilledButton(
              onPressed: pro.purchasing ? null : onBuy,
              child: pro.purchasing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Continue'),
            ),
          const SizedBox(height: Space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Required by both stores, and by the Shipaton checklist.
              TextButton(
                onPressed: pro.purchasing ? null : onRestore,
                child: const Text('Restore purchases'),
              ),
              const Text('·', style: TextStyle(color: PlateColors.inkSoft)),
              TextButton(
                onPressed: () => _open(PaywallScreen.privacyPolicyUrl),
                child: const Text('Privacy'),
              ),
              const Text('·', style: TextStyle(color: PlateColors.inkSoft)),
              TextButton(
                onPressed: () => _open(PaywallScreen.termsUrl),
                child: const Text('Terms'),
              ),
            ],
          ),
          Text(
            'Subscriptions renew automatically until cancelled. Manage or cancel any '
            'time in Google Play.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
