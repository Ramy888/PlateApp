import 'package:flutter/material.dart';

import '../theme.dart';

/// The app's one card shape. Everything raised off the cream background uses it.
class PlateCard extends StatelessWidget {
  const PlateCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
    this.color = PlateColors.card,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(kRadius);
    return Material(
      color: color,
      borderRadius: shape,
      child: InkWell(
        onTap: onTap,
        borderRadius: shape,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: border ?? Colors.transparent, width: 2),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A large tappable row used for goals and preferences: emoji, label, blurb,
/// and a check. Big targets, because this is the first thing anyone touches.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.showIndicator = true,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Off where the tap is an immediate action rather than a selection — an
  /// empty checkbox there wrongly implies a confirm step is coming.
  final bool showIndicator;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: PlateCard(
        onTap: onTap,
        color: selected ? PlateColors.greenSel : PlateColors.card,
        border: selected ? PlateColors.green : null,
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            if (showIndicator)
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? PlateColors.green : Colors.transparent,
                  border: Border.all(
                    color: selected ? PlateColors.green : PlateColors.neutral400,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 17, color: PlateColors.neutral100)
                    : const SizedBox.shrink(),
              )
            else
              const Icon(Icons.chevron_right, color: PlateColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Small pill used for "Pro", "Fastest", "Cheapest", "Plant-based".
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.emoji,
    this.background = PlateColors.greenSoft,
    this.foreground = PlateColors.green,
  });

  final String label;
  final String? emoji;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(kPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty states and locked states share this shape so the app never shows a
/// blank rectangle with nothing to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.message,
    this.action,
  });

  final String emoji;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: PlateColors.card,
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 30)),
            ),
            const SizedBox(height: Space.md),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.sm),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            if (action != null) ...[const SizedBox(height: Space.lg), action!],
          ],
        ),
      ),
    );
  }
}
