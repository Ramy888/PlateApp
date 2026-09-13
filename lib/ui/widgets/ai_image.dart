import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';

/// A generated picture of a plate, wherever one is shown.
///
/// One widget for all four places — the result page, a chat reply, a spoken
/// reply and a saved patch — because the label on it is a commitment made to
/// Google on the AI-generated content form, and four copies of a commitment
/// drift. Declared there as labelled *non-dismissibly*.
///
/// The label is a badge on the picture rather than a sentence under it. It
/// costs no reading, it cannot be scrolled away from the thing it describes,
/// and it follows the image into full screen. What is left underneath is the
/// part people actually need: this is not a photograph of your food, and the
/// helping shown means nothing.
class AiImage extends StatelessWidget {
  const AiImage({super.key, required this.bytes, this.height = 220});

  final Uint8List bytes;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'AI picture of your plate. Tap to see it larger.',
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                opaque: false,
                barrierColor: PlateColors.ink,
                pageBuilder: (_, _, _) => _FullScreen(bytes: bytes),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              child: Stack(
                children: [
                  SizedBox(
                    height: height,
                    width: double.infinity,
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  ),
                  const Positioned(top: Space.sm, left: Space.sm, child: _AiBadge()),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Appearance and serving size are illustrative.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontSize: 12.5, color: PlateColors.inkSoft),
        ),
      ],
    );
  }
}

/// The disclosure, on the picture it is about.
class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // Dark enough to read on a bright plate and a dim one alike; a badge
        // that disappears on some images is not a label.
        color: PlateColors.ink.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(kPill),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sparkles, size: 12, color: PlateColors.neutral100),
            SizedBox(width: 5),
            Text(
              'AI picture',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: PlateColors.neutral100,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picture, as big as the screen allows.
class _FullScreen extends StatelessWidget {
  const _FullScreen({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping the backdrop closes it, which is what everyone tries
          // first.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
            ),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          // The label comes with it. A picture opened full screen is the one
          // most likely to be screenshotted and sent on.
          const Positioned(top: 0, left: 0, right: 0, child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(Space.md),
              child: Row(children: [_AiBadge()]),
            ),
          )),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, color: PlateColors.neutral100),
                  style: IconButton.styleFrom(
                    backgroundColor: PlateColors.ink.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
