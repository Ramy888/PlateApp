import 'package:flutter/material.dart';

import '../data/purchases_service.dart' show storeName;
import 'theme.dart';

/// Privacy policy and terms, shipped inside the app.
///
/// Play also requires a hosted policy URL for the store listing (see
/// `docs/privacy.html`), but linking out from the app is a dead end when the
/// device is offline or the host moves. The text here is the same document.
class LegalScreen extends StatelessWidget {
  const LegalScreen._({required this.title, required this.sections});

  final String title;
  final List<(String, String)> sections;

  static Future<void> showPrivacy(BuildContext context) => _show(
        context,
        LegalScreen._(title: 'Privacy policy', sections: _privacy),
      );

  static Future<void> showTerms(BuildContext context) => _show(
        context,
        LegalScreen._(title: 'Terms of use', sections: _terms),
      );

  static Future<void> _show(BuildContext context, LegalScreen screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
          children: [
            Text('Last updated 6 September 2026',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: Space.lg),
            for (final (heading, body) in sections) ...[
              Text(heading, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.sm),
              Text(body, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: Space.lg),
            ],
          ],
        ),
      ),
    );
  }

  static List<(String, String)> get _privacy => <(String, String)>[
    (
      'The short version',
      'PlatePatch has no accounts and no server of its own. What you tap stays on '
          'your phone. We cannot see your meals, your goals or your history, because '
          'they are never sent anywhere.'
    ),
    (
      'What is stored on your device',
      'Your goal, your dietary and budget preferences, the meals you have saved, and '
          'your after-meal check answers. All of it lives in your phone’s app '
          'storage. Uninstalling PlatePatch deletes it.'
    ),
    (
      'What leaves your device',
      'Only what a purchase requires. If you subscribe to PlatePatch Pro, $storeName '
          'processes the payment and RevenueCat — the service that manages the '
          'subscription — receives a purchase record and an anonymous identifier for '
          'your device so your subscription can be restored later. No meal data, no '
          'preferences and no health information is ever included.'
    ),
    (
      'What we do not collect',
      'No name, no email address, no phone number, no location, no contacts, no '
          'photos, no advertising identifier. There is no analytics SDK and no '
          'advertising in PlatePatch.'
    ),
    (
      'Children',
      'PlatePatch is a general-audience app and is not directed at children under 13. '
          'We do not knowingly collect information from them.'
    ),
    (
      'This is not medical advice',
      'PlatePatch offers simple, general food suggestions. It is not a medical device, '
          'it does not diagnose or treat anything, and it is not a substitute for '
          'advice from a doctor or a registered dietitian. If you have a medical '
          'condition, an allergy, or are pregnant, talk to a professional before '
          'changing what you eat.'
    ),
    (
      'Your choices',
      'You can clear everything by removing saved patches in the app, or by '
          'uninstalling PlatePatch. To cancel a subscription, use $storeName’s '
          'subscription settings.'
    ),
    (
      'Contact',
      'Questions about this policy: support@platepatch.app'
    ),
  ];

  static List<(String, String)> get _terms => <(String, String)>[
    (
      'Using PlatePatch',
      'PlatePatch suggests one thing you might add to a meal. Use it as a nudge, not '
          'as a rule. You are responsible for what you choose to eat.'
    ),
    (
      'Not medical or dietary advice',
      'The suggestions are general and are generated from a fixed set of rules. They '
          'do not account for allergies, intolerances, medications or medical '
          'conditions. Always check ingredients yourself, and speak to a qualified '
          'professional about your own needs.'
    ),
    (
      'PlatePatch Pro',
      'Pro is an auto-renewing subscription billed through $storeName. Where a free '
          'trial is offered, it converts to a paid subscription unless cancelled '
          'before it ends. Prices are shown in the app before you confirm. You can '
          'cancel at any time in $storeName; cancelling stops future renewals and '
          'leaves the current period running to its end.'
    ),
    (
      'Refunds',
      'Purchases are handled by $storeName, so refunds follow $storeName’s '
          'refund policy.'
    ),
    (
      'Changes',
      'These terms may change as the app changes. Continuing to use PlatePatch after '
          'an update means the updated terms apply.'
    ),
    (
      'Contact',
      'support@platepatch.app'
    ),
  ];
}
