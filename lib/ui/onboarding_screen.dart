import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Welcome, goal, preferences — three steps, no account, no questions about
/// weight or calories. The whole point is that nothing here feels like a form.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      ref.read(settingsProvider.notifier).completeOnboarding();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ProgressDots(count: _pageCount, active: _page),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _WelcomePage(),
                  _GoalPage(
                    selected: settings.goal,
                    onSelect: (g) => ref.read(settingsProvider.notifier).setGoal(g),
                  ),
                  _PrefsPage(
                    selected: settings.dietPrefs,
                    onToggle: (p) => ref.read(settingsProvider.notifier).togglePref(p),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
              child: FilledButton(
                onPressed: _next,
                child: Text(_page == _pageCount - 1 ? 'Start patching' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 6,
              width: i == active ? 24 : 6,
              decoration: BoxDecoration(
                color: i == active ? PlateColors.green : PlateColors.neutral300,
                borderRadius: BorderRadius.circular(kPill),
              ),
            ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, this.subtitle, required this.children});

  final String title;

  /// Omitted on the opening page: the film says it, and a paragraph over the
  /// top of it is the app explaining a picture nobody has watched yet.
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.lg),
      children: [
        Text(title, style: Theme.of(context).textTheme.displaySmall),
        if (subtitle != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            subtitle!,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: PlateColors.inkSoft),
          ),
        ],
        const SizedBox(height: Space.lg),
        ...children,
      ],
    );
  }
}

/// The opening four seconds.
///
/// A film rather than three written beats, because the whole idea — a hot meal,
/// one thing added to it, and someone pleased about it — is quicker to watch
/// than to read. The words that stayed are the ones the picture cannot say.
class _WelcomePage extends StatefulWidget {
  const _WelcomePage();

  @override
  State<_WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<_WelcomePage> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final video = VideoPlayerController.asset('assets/onboarding/intro.mp4');
    try {
      await video.initialize();
      await video.setVolume(0);
      await video.setLooping(true);
      await video.play();
    } catch (_) {
      // A device that cannot decode it still gets the whole page; the
      // placeholder below stands in. Onboarding must never be a blank screen.
      // Disposing is itself a platform call, so it gets its own guard — in a
      // widget test there is no channel and this is exactly the path taken.
      try {
        await video.dispose();
      } catch (_) {}
      return;
    }
    if (!mounted) {
      await video.dispose();
      return;
    }
    setState(() => _video = video);
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    // Someone who has asked their phone to stop moving things has asked this
    // to stop too — they get the first frame, held.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && video != null && video.value.isPlaying) {
      video.pause();
    }

    return _Page(
      title: 'One small thing,\nadded to what you already eat.',
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kRadius),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: video == null
                ? const Skeleton(height: double.infinity, radius: 0)
                : FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: video.value.size.width,
                      height: video.value.size.height,
                      child: VideoPlayer(video),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _GoalPage extends StatelessWidget {
  const _GoalPage({required this.selected, required this.onSelect});

  final Goal selected;
  final ValueChanged<Goal> onSelect;


  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'What would help most?',
      subtitle: 'This only changes which suggestion comes first. Change it any time.',
      children: [
        for (final goal in Goal.values) ...[
          ChoiceRow(
            icon: goal.icon,
            title: goal.label,
            subtitle: goal.blurb,
            selected: selected == goal,
            onTap: () => onSelect(goal),
          ),
          const SizedBox(height: Space.sm),
        ],
      ],
    );
  }
}

class _PrefsPage extends StatelessWidget {
  const _PrefsPage({required this.selected, required this.onToggle});

  final Set<DietPref> selected;
  final ValueChanged<DietPref> onToggle;


  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Anything to leave out?',
      subtitle: 'Pick as many as you like, or none at all.',
      children: [
        for (final pref in DietPref.values) ...[
          ChoiceRow(
            icon: pref.icon,
            title: pref.label,
            subtitle: pref.blurb,
            selected: selected.contains(pref),
            onTap: () => onToggle(pref),
          ),
          const SizedBox(height: Space.sm),
        ],
      ],
    );
  }
}
