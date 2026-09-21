import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/voice_service.dart';
import '../domain/models.dart';
import '../state/chat_providers.dart';
import '../state/providers.dart';
import '../state/save_patch.dart';
import 'icons.g.dart';
import 'paywall_screen.dart';
import 'theme.dart';
import 'widgets/ai_image.dart';
import 'widgets/common.dart';
import 'widgets/plate_diagram.dart';
import 'widgets/report_sheet.dart';

/// Say what you are eating.
///
/// Hold the button, talk, let go. What was heard comes back on screen before it
/// is acted on — the same confirm-before-you-trust-it rule the camera has, for
/// the same reason: the model is confident even when it has misheard.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

enum _Stage { idle, listening, thinking, answered }

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  _Stage _stage = _Stage.idle;
  String? _problem;

  /// How the current message should be said. Running out of free tries is an
  /// offer; everything else on this screen is guidance.
  NoticeTone _problemTone = NoticeTone.guidance;

  /// What was last recorded, kept so it can be heard again.
  ///
  /// When an answer comes back wrong the first question is always "did it
  /// mishear me, or misunderstand me?", and until now the app gave no way to
  /// tell. The recording is held in memory for the session and never written
  /// to disk — the file the recorder made is already deleted by the time this
  /// is set.
  VoiceClip? _clip;
  bool _playing = false;
  StreamSubscription<void>? _playbackEnded;

  /// Resolved once, eagerly. dispose() needs it, and reading a provider
  /// through a context that is being torn down is not safe — a `late final`
  /// would not help, because its first read would be that one.
  late VoiceService _voice;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceServiceProvider);
    _playbackEnded = _voice.playbackFinished.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _playbackEnded?.cancel();
    // Stop the microphone and the speaker with the screen, whatever state the
    // turn was left in.
    _voice.stopPlayback();
    _voice.stopSpeaking();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (_stage != _Stage.idle && _stage != _Stage.answered) return;

    await _voice.stopSpeaking();
    if (!await _voice.hasPermission()) {
      if (!mounted) return;
      setState(() {
        _problem =
            'The Plate needs the microphone to hear you. You can still type or photograph a meal.';
        _problemTone = NoticeTone.guidance;
      });
      return;
    }

    try {
      await _voice.startRecording();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.listening;
        _problem = null;
        _clip = null;
        _playing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _problem = 'The microphone could not be started.';
        _problemTone = NoticeTone.trouble;
      });
    }
  }

  /// Saves the answer and puts the screen back to a fresh prompt.
  ///
  /// The voice screen and the chat screen share one conversation, and chat
  /// already cleared it on save. Voice did not, so the saved meal stayed on
  /// screen and the next thing you said was appended underneath a plate you
  /// had already dealt with.
  void _saveAndReset(ChatMessage message, Addition addition) {
    savePatch(
      context,
      ref,
      slot: ref.read(mealDraftProvider).slot,
      foodIds: message.foodIds,
      addition: addition,
      image: message.image,
      returnToStart: false,
      clearConversation: true,
    );
    setState(() {
      _stage = _Stage.idle;
      _clip = null;
      _playing = false;
      _problem = null;
    });
  }

  Future<void> _togglePlayback() async {
    final clip = _clip;
    if (clip == null) return;
    if (_playing) {
      await _voice.stopPlayback();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    await _voice.playClip(clip);
  }

  Future<void> _stopAndSend() async {
    if (_stage != _Stage.listening) return;
    setState(() => _stage = _Stage.thinking);

    VoiceClip? clip;
    try {
      clip = await _voice.stopRecording();
    } catch (_) {
      clip = null;
    }

    if (clip == null) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _problem = 'That was too short to hear. Hold the button while you speak.';
        _problemTone = NoticeTone.guidance;
      });
      return;
    }

    if (mounted) setState(() => _clip = clip);

    await ref.read(chatControllerProvider.notifier).sendClip(clip);
    if (!mounted) return;

    final chat = ref.read(chatControllerProvider);
    // Running out mid-sentence is a moment to sell, not an error — so the
    // message is read before it is shown, and shown in the offer tone.
    final upgrade = ref.read(chatControllerProvider.notifier).takeUpgrade();
    setState(() {
      _stage = _Stage.answered;
      _problem = chat.problem;
      _problemTone = upgrade != null ? NoticeTone.offer : NoticeTone.trouble;
    });

    if (upgrade != null) {
      await PaywallScreen.show(
        context,
        reason: upgrade.isTrialEnded ? 'Keep talking to The Plate' : 'More AI meal chats',
      );
      if (!mounted) return;
      // Someone who came back from the paywall having paid should not still be
      // reading the sentence that sent them there.
      if (ref.read(proProvider).isPro) setState(() => _problem = null);
      return;
    }

    // The answer is read back, because the whole point of speaking is not
    // having to look at the screen.
    final last = chat.messages.isEmpty ? null : chat.messages.last;
    if (last != null && !last.isUser && !last.failed) {
      await _voice.speak(last.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    // The last exchange only. This screen is a conversation you are having, not
    // one you are reading back — the thread lives on the chat screen.
    final recent = chat.messages.length <= 2
        ? chat.messages
        : chat.messages.sublist(chat.messages.length - 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Say your meal')),
      // The button floats over the conversation rather than sitting in a row
      // beneath it: it is the one control on the screen and it should not cost
      // the answer a third of the height. Nothing is drawn behind it, so the
      // reply scrolls past underneath.
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: _stage == _Stage.answered && recent.isNotEmpty
                  ? _Exchange(
                      messages: recent,
                      bottomInset: _micInset,
                      onSave: _saveAndReset,
                    )
                  : _Prompt(stage: _stage, bottomInset: _micInset),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: Space.lg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_clip != null && _stage == _Stage.answered) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
                      child: _PlayBack(
                        playing: _playing,
                        onTap: _togglePlayback,
                      ),
                    ),
                  ],
                  if (_problem != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                      child: Notice(_problem!, tone: _problemTone),
                    ),
                  _HoldToTalk(
                    stage: _stage,
                    onDown: _startListening,
                    onUp: _stopAndSend,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much room the floating button needs at the foot of the scroll, so the
/// last line of an answer is readable rather than tucked behind it.
const double _micInset = 196;

/// What the screen says while there is nothing to show yet.
class _Prompt extends StatelessWidget {
  const _Prompt({required this.stage, this.bottomInset = 0});

  final _Stage stage;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (stage) {
      _Stage.listening => (
          LucideIcons.audioLines,
          'Listening…',
          'Say what is on the plate, then let go.',
        ),
      _Stage.thinking => (
          LucideIcons.loader,
          'Reading your plate…',
          'One moment.',
        ),
      _ => (
          LucideIcons.mic,
          'Hold and say your meal',
          'Something like "rice and grilled chicken". I will say it back, '
              'suggest one thing to add, and read it out.',
        ),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: EmptyState(icon: icon, title: title, message: message),
    );
  }
}

/// The last thing said, and the answer to it.
class _Exchange extends ConsumerWidget {
  const _Exchange({
    required this.messages,
    required this.onSave,
    this.bottomInset = 0,
  });

  final List<ChatMessage> messages;
  final double bottomInset;

  /// Saving belongs to the screen, not the list: it has to put the screen back
  /// to a fresh prompt afterwards.
  final void Function(ChatMessage, Addition) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md + bottomInset),
      children: [
        for (final message in messages) ...[
          if (message.isUser)
            _Heard(text: message.text)
          else
            _Answer(message: message, onSave: onSave),
          const SizedBox(height: Space.md),
        ],
      ],
    );
  }
}

/// What the model heard, shown plainly so a mishearing is obvious before
/// anything is done about it.
class _Heard extends StatelessWidget {
  const _Heard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.quote, size: 13, color: PlateColors.inkSoft),
            const SizedBox(width: 6),
            Text('What I heard', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(text, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _Answer extends ConsumerWidget {
  const _Answer({required this.message, required this.onSave});

  final ChatMessage message;
  final void Function(ChatMessage, Addition) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final addition = catalog.additions.where((a) => a.id == message.additionId);

    return PlateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.text, style: Theme.of(context).textTheme.bodyLarge),
          if (addition.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            PatchHighlight(
              icon: catalogIcon(addition.first.icon),
              name: addition.first.name,
              how: addition.first.how,
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              onPressed: () => onSave(message, addition.first),
              icon: const Icon(LucideIcons.bookmark, size: 17),
              label: const Text("I'll add this"),
            ),
          ],
          if (message.image == null && message.additionId.isNotEmpty) ...[
            // Spoken answers get a picture too. The photograph does not
            // survive the session and needs an allowance; this is drawn from
            // the ids the reply already carries, so a voice turn is never the
            // one entry point that answers in words alone.
            const SizedBox(height: Space.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              child: ColoredBox(
                color: PlateColors.cream,
                child: SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: _SpokenPlate(message: message),
                  ),
                ),
              ),
            ),
          ],
          if (message.image != null) ...[
            const SizedBox(height: Space.md),
            AiImage(bytes: message.image!, height: 220),
          ],
          const SizedBox(height: Space.sm),
          _Feedback(message: message),
        ],
      ),
    );
  }
}

/// Rating and reporting, on a spoken reply exactly as on a typed one — Play
/// asks for it on generated content, not on generated text.
class _Feedback extends ConsumerWidget {
  const _Feedback({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rated = message.rating;
    void rate(bool helpful) =>
        ref.read(chatControllerProvider.notifier).rate(message, helpful: helpful);

    return Row(
      children: [
        IconButton(
          tooltip: 'Helpful',
          visualDensity: VisualDensity.compact,
          onPressed: rated == null ? () => rate(true) : null,
          icon: Icon(LucideIcons.thumbsUp,
              size: 17, color: rated == true ? PlateColors.green : PlateColors.inkSoft),
        ),
        IconButton(
          tooltip: 'Not helpful',
          visualDensity: VisualDensity.compact,
          onPressed: rated == null ? () => rate(false) : null,
          icon: Icon(LucideIcons.thumbsDown,
              size: 17, color: rated == false ? PlateColors.green : PlateColors.inkSoft),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Report this reply',
          visualDensity: VisualDensity.compact,
          icon: const Icon(LucideIcons.flag, size: 17, color: PlateColors.inkSoft),
          onPressed: () => ReportSheet.show(context),
        ),
      ],
    );
  }
}

/// Hold to talk.
///
/// Held rather than toggled: the gesture ends the turn, so there is no state
/// where the app is listening and nobody realises. The ring grows while it
/// listens, so the screen is visibly doing what the microphone is doing.
class _HoldToTalk extends StatefulWidget {
  const _HoldToTalk({required this.stage, required this.onDown, required this.onUp});

  final _Stage stage;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<_HoldToTalk> createState() => _HoldToTalkState();
}

class _HoldToTalkState extends State<_HoldToTalk> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didUpdateWidget(_HoldToTalk old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  /// The ring only turns while the microphone is on. An animation that never
  /// stops costs battery for nothing, and it means the screen is never at rest.
  void _syncPulse() {
    final listening = widget.stage == _Stage.listening;
    if (listening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!listening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listening = widget.stage == _Stage.listening;
    final busy = widget.stage == _Stage.thinking;

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: GestureDetector(
            onTapDown: busy ? null : (_) => widget.onDown(),
            onTapUp: busy ? null : (_) => widget.onUp(),
            onTapCancel: busy ? null : widget.onUp,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (listening)
                      Container(
                        width: 96 + 44 * _pulse.value,
                        height: 96 + 44 * _pulse.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: PlateColors.green
                              .withValues(alpha: 0.16 * (1 - _pulse.value)),
                        ),
                      ),
                    child!,
                  ],
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: listening ? 104 : 96,
                height: listening ? 104 : 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: busy ? PlateColors.neutral300 : PlateColors.green,
                ),
                child: busy
                    ? const ThinkingDots()
                    : Icon(
                        listening ? LucideIcons.audioLines : LucideIcons.mic,
                        size: 38,
                        color: PlateColors.neutral100,
                      ),
              ),
            ),
          ),
        ),
        Text(
          switch (widget.stage) {
            _Stage.listening => 'Listening — let go when you are done',
            _Stage.thinking => 'Reading your plate…',
            _ => 'Hold to talk',
          },
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// The plate a spoken reply described.
///
/// Same as the chat one, and for the same reason: the ids outlive the picture.
class _SpokenPlate extends ConsumerWidget {
  const _SpokenPlate({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final foods = [
      for (final id in message.foodIds) ...catalog.foods.where((f) => f.id == id),
    ];
    final addition = catalog.additions.where((a) => a.id == message.additionId);
    return PlateDiagram(
      foods,
      addition: addition.isEmpty ? null : addition.first,
    );
  }
}

/// What you just said, playable.
///
/// Deliberately not a waveform. The recording is held as opaque bytes and
/// drawing a shape over it would be decoration pretending to be data — this
/// says what it is and offers the one thing that matters, which is hearing it
/// back. When an answer looks wrong, this is how someone tells a mishearing
/// from a misunderstanding.
class _PlayBack extends StatelessWidget {
  const _PlayBack({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(kPill);
    return Semantics(
      button: true,
      label: playing ? 'Stop playing what you said' : 'Hear what you said',
      child: Material(
        color: PlateColors.card,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: PlateColors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      playing ? LucideIcons.square : LucideIcons.play,
                      size: 15,
                      color: PlateColors.neutral100,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  playing ? 'Playing what you said' : 'Hear what you said',
                  style: const TextStyle(fontSize: 15, color: PlateColors.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
