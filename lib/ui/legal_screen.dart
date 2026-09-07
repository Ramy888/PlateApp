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
      'The Plate has no accounts. Your meals, goals and history stay on your '
          'phone and are never uploaded. The one exception is scanning: if you '
          'photograph a meal, that photo is sent to be described, and then '
          'discarded. Everything else in the app works with no network at all.'
    ),
    (
      'What is stored on your device',
      'Your goal, your dietary and budget preferences, the meals you have saved, '
          'your after-meal check answers, and any photos you scan. All of it lives '
          'in your phone’s app storage. Uninstalling The Plate deletes it.'
    ),
    (
      'What happens to a photo you scan',
      'Before it leaves your phone, the photo is cropped to the guide circle, '
          'resized, and stripped of all metadata — so no location, no device model '
          'and no timestamp travel with it. It is then sent through The Plate’s '
          'server to Google’s Gemini API, which describes the food it can see. '
          'The Plate does not store the photo, and Google does not use it to train '
          'its models. If you generate a visual preview, that generated image is '
          'held for up to 24 hours so your phone can download it, then deleted '
          'automatically.'
    ),
    (
      'What our server keeps',
      'An anonymous device identifier, so a scan allowance can be counted. A record '
          'that a scan happened — the time it took and whether food was found — with '
          'no photo and no food names in it. And any report you send us about an AI '
          'result. There is no account, no email address and no name attached to any '
          'of it.'
    ),
    (
      'Purchases',
      'If you subscribe to Plate Pro, $storeName processes the payment and '
          'RevenueCat — the service that manages the subscription — receives a '
          'purchase record and an anonymous identifier for your device so your '
          'subscription can be restored later. No meal data and no health '
          'information is ever included.'
    ),
    (
      'What we do not collect',
      'No name, no email address, no phone number, no location, no contacts, no '
          'advertising identifier. There is no analytics SDK and no advertising in '
          'The Plate, and your meal history is never uploaded.'
    ),
    (
      'The Plate uses AI, and AI is wrong sometimes',
      'Food recognition and visual previews are produced by a generative AI model. '
          'It misreads things. That is why you confirm what it saw before anything '
          'is suggested, why a generated preview is labelled as illustrative, and '
          'why every AI result has a Report control on it.'
    ),
    (
      'Children',
      'The Plate is a general-audience app and is not directed at children under 13. '
          'We do not knowingly collect information from them.'
    ),
    (
      'This is not medical advice',
      'The Plate offers simple, general food suggestions. It is not a medical device, '
          'it does not diagnose or treat anything, and it is not a substitute for '
          'advice from a doctor or a registered dietitian. If you have a medical '
          'condition, an allergy, or are pregnant, talk to a professional before '
          'changing what you eat.'
    ),
    (
      'Deleting your data',
      'Settings has a “Delete my data” control. It erases what is on your phone and '
          'tells our server to forget your device — its identifier, its scan '
          'allowance, its scan records and any reports. Uninstalling the app also '
          'removes everything stored on the phone. To cancel a subscription, use '
          '$storeName’s subscription settings; cancelling and deleting are separate.'
    ),
    (
      'Contact',
      'Questions about this policy: support@platepatch.app'
    ),
  ];

  static List<(String, String)> get _terms => <(String, String)>[
    (
      'Using The Plate',
      'The Plate suggests one thing you might add to a meal. Use it as a nudge, not '
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
      'AI results are not facts',
      'The Plate uses AI to read a photo of your meal and, optionally, to generate a '
          'picture of what it might look like with something added. Both get things '
          'wrong. Recognised food is shown to you for confirmation before anything is '
          'suggested, and a generated image is an illustration — not a photograph of '
          'real food, and not a guide to portion size. Never rely on either to judge '
          'whether something is safe for you to eat.'
    ),
    (
      'Plate Pro',
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
      'These terms may change as the app changes. Continuing to use The Plate after '
          'an update means the updated terms apply.'
    ),
    (
      'Contact',
      'support@platepatch.app'
    ),
  ];
}
