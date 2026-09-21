import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/purchases_service.dart';
import '../theme.dart';
import 'common.dart';

/// Where someone with a code types it.
///
/// Play has no in-app redemption API — Google says so plainly — so this cannot
/// finish the job itself. What it can do is remove the part people actually
/// fail at: finding Redeem in the Play Store, buried in a menu, and typing a
/// long code by hand. Here they paste it once and Play opens with it filled in.
///
/// The half that makes this work is elsewhere: the app syncs with the store
/// when it returns to the foreground, so a code redeemed in Play is picked up
/// on the way back. Before that, a redeemed code left the subscription
/// invisible until someone found Restore purchases in settings.
class PromoCodeSheet extends StatefulWidget {
  const PromoCodeSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: PlateColors.cream,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
        ),
        builder: (_) => const PromoCodeSheet(),
      );

  @override
  State<PromoCodeSheet> createState() => _PromoCodeSheetState();
}

class _PromoCodeSheetState extends State<PromoCodeSheet> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _code.text.trim().length >= 4;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Have a promo code?',
              style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: Space.sm),
          Text(
            'Paste it here and Google Play will open with the code already '
            'filled in. Come back when you are done and Plate Pro will be on.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: PlateColors.inkSoft,
                ),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Your code',
              filled: true,
              fillColor: PlateColors.neutral100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusSmall),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: ready
                  ? () {
                      openRedeemCode(_code.text);
                      Navigator.of(context).pop();
                    }
                  : null,
              icon: const Icon(LucideIcons.externalLink, size: 17),
              label: const Text('Redeem in Google Play'),
            ),
          ),
          const SizedBox(height: Space.sm),
          const Inset(
            icon: LucideIcons.info,
            child: Text(
              'Codes are redeemed by Google Play, not by The Plate. You can '
              'also redeem one on the payment screen while subscribing.',
            ),
          ),
        ],
      ),
    );
  }
}
