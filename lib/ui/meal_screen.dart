import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'chat_screen.dart';
import 'food_picker_screen.dart';
import 'saved_screen.dart';
import 'scan_camera_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets/mic_button.dart';
import 'widgets/transitions.dart';

/// The hub.
///
/// One question — which meal? — and three ways to answer what is on it: tap the
/// meal and pick the food, say it, or photograph it. Everything below the pager
/// is a way in, and each opens a page of its own rather than growing this one.
class MealScreen extends ConsumerWidget {
  const MealScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(mealDraftProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: Space.lg,
        title: const _Brand(),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(LucideIcons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The pager takes a share of what is left after the fixed
            // furniture, within limits — tall enough to read as the subject of
            // the screen, never so tall that the ways in are pushed off a small
            // phone. It is then centred in whatever room remains, so a tall
            // screen gets even margins rather than one dead band in the middle.
            final pagerHeight = (constraints.maxHeight * 0.40).clamp(200.0, 300.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Text(
                    'What are you eating?',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      height: pagerHeight,
                      child: _SlotPager(
                        selected: draft.slot,
                        onSelect: (s) => ref.read(mealDraftProvider.notifier).setSlot(s),
                        onOpen: (s) {
                          ref.read(mealDraftProvider.notifier).setSlot(s);
                          Navigator.of(context).push(slideUpRoute(FoodPickerScreen(slot: s)));
                        },
                      ),
                    ),
                  ),
                ),
                _WaysIn(slot: draft.slot),
                const SizedBox(height: Space.md),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The mark and the name together, so the top of the screen says whose app this
/// is without spending a whole row on it.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/icon/icon.png',
            width: 30,
            height: 30,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: Space.sm),
        Text('The Plate', style: Theme.of(context).appBarTheme.titleTextStyle),
      ],
    );
  }
}

/// The three ways to say what is on the plate, sized against each other: the
/// typed one is a full-width field because it takes the most saying; the spoken
/// and photographed ones are round because they take none.
class _WaysIn extends StatelessWidget {
  const _WaysIn({required this.slot});

  final MealSlot slot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        children: [
          const _ChatField(),
          const SizedBox(height: Space.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundAction(
                icon: LucideIcons.camera,
                label: 'Scan my meal',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ScanCameraScreen(slot: slot)),
                ),
              ),
              // The mic reserves room for its own ripple, so the three sit on
              // balanced centres rather than balanced boxes.
              MicButton(
                tooltip: 'Speak your meal',
                onTap: () => Navigator.of(context).push(slideUpRoute(const ChatScreen())),
              ),
              _RoundAction(
                icon: LucideIcons.bookmark,
                label: 'Saved patches',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SavedScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A quiet round action. Smaller and flatter than the mic, because the mic is
/// the one this screen is pointing at.
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: PlateColors.card,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, size: 22, color: PlateColors.green),
            ),
          ),
        ),
      ),
    );
  }
}

/// Looks like a composer, behaves like a button: tapping it opens the
/// conversation rather than starting one in place.
class _ChatField extends StatelessWidget {
  const _ChatField();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Describe your meal in words',
      child: Material(
        color: PlateColors.neutral100,
        borderRadius: BorderRadius.circular(kPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(kPill),
          onTap: () => Navigator.of(context).push(slideUpRoute(const ChatScreen())),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Row(
              children: [
                const Icon(LucideIcons.messageCircle, size: 19, color: PlateColors.green),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Describe your meal…',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: PlateColors.inkSoft,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The meal, as three big cards you swipe between.
///
/// Landing on a card selects it; tapping the one you are on opens the food for
/// it. A swipe is browsing and a tap is committing — the distinction a deck of
/// cards already teaches.
class _SlotPager extends StatefulWidget {
  const _SlotPager({
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final MealSlot selected;
  final ValueChanged<MealSlot> onSelect;
  final ValueChanged<MealSlot> onOpen;

  @override
  State<_SlotPager> createState() => _SlotPagerState();
}

class _SlotPagerState extends State<_SlotPager> {
  late final PageController _controller = PageController(
    initialPage: MealSlot.values.indexOf(widget.selected),
    // A sliver of the neighbouring cards shows, so it reads as a deck.
    viewportFraction: 0.82,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      itemCount: MealSlot.values.length,
      onPageChanged: (i) => widget.onSelect(MealSlot.values[i]),
      itemBuilder: (context, i) {
        final slot = MealSlot.values[i];
        final selected = slot == widget.selected;
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.sm),
          child: _SlotCard(
            slot: slot,
            selected: selected,
            onTap: () => selected
                ? widget.onOpen(slot)
                : _controller.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                  ),
          ),
        );
      },
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.selected, required this.onTap});

  final MealSlot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(kRadius);
    return Semantics(
      button: true,
      selected: selected,
      label: '${slot.label}. Tap to pick what is on the plate.',
      child: AnimatedScale(
        // The card you are on stands slightly proud of its neighbours.
        scale: selected ? 1 : 0.94,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Material(
          color: selected ? PlateColors.green : PlateColors.card,
          borderRadius: shape,
          child: InkWell(
            onTap: onTap,
            borderRadius: shape,
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? PlateColors.neutral100.withValues(alpha: 0.16)
                            : PlateColors.neutral100,
                        borderRadius: BorderRadius.circular(kRadiusSmall),
                      ),
                      child: Icon(
                        slot.icon,
                        size: 72,
                        color: selected ? PlateColors.neutral100 : PlateColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    slot.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: selected ? PlateColors.neutral100 : PlateColors.ink,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selected ? 'Tap to pick the food' : 'Swipe to choose',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: selected
                              ? PlateColors.neutral100.withValues(alpha: 0.75)
                              : PlateColors.inkSoft,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
