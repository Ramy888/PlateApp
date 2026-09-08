import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/chat_providers.dart';
import 'icons.g.dart';
import 'paywall_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/report_sheet.dart';
import 'widgets/transitions.dart';

/// Describe the meal in words, and get it back with one thing added.
///
/// The other way into the same answer the camera gives, for the times a photo
/// is awkward — a lunch already half eaten, a dish with a name but no plate in
/// front of you yet.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  static Future<void> show(BuildContext context) =>
      Navigator.of(context).push(slideUpRoute(const ChatScreen()));

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await ref.read(chatControllerProvider.notifier).send(text);
    if (!mounted) return;

    // Running out mid-conversation is a moment to sell, not an error.
    final upgrade = ref.read(chatControllerProvider.notifier).takeUpgrade();
    if (upgrade != null) {
      await PaywallScreen.show(
        context,
        reason: upgrade.isTrialEnded ? 'Keep chatting about meals' : 'More AI meal chats',
      );
    }
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Describe your meal'),
        actions: [
          if (!chat.isEmpty)
            IconButton(
              tooltip: 'Clear this conversation',
              icon: const Icon(LucideIcons.trash2),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: chat.isEmpty
                  ? const _Opening()
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
                      itemCount: chat.messages.length + (chat.sending ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                      itemBuilder: (_, i) {
                        if (i == chat.messages.length) return const _Thinking();
                        return _Bubble(message: chat.messages[i]);
                      },
                    ),
            ),
            _Composer(
              controller: _composer,
              sending: chat.sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PlateColors.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        title: Text('Clear this conversation?',
            style: Theme.of(dialogContext).textTheme.titleLarge),
        content: Text(
          'It is only on this phone, so clearing it removes it for good.',
          style: Theme.of(dialogContext).textTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: PlateColors.pro),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes ?? false) await ref.read(chatControllerProvider.notifier).clear();
  }
}

/// What the screen says before anyone has typed anything.
class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: LucideIcons.messageCircle,
      title: 'Tell me what you are eating',
      message:
          'In your own words — "rice and grilled chicken", "leftover pasta". '
          'I will say it back, suggest one thing to add, and draw the plate.',
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 12),
            decoration: BoxDecoration(
              color: PlateColors.greenSel,
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Text(message.text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        child: message.failed
            ? PlateCard.pro(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.circleAlert, size: 18, color: PlateColors.pro),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(message.text,
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  ],
                ),
              )
            : PlateCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.text, style: Theme.of(context).textTheme.bodyLarge),
                    if (message.image != null) ...[
                      const SizedBox(height: Space.md),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(kRadiusSmall),
                        child: Image.memory(
                          message.image!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      // The label Play expects, on the image it is about, and
                      // never dismissible.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.sparkles, size: 13, color: PlateColors.inkSoft),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'AI picture — appearance and serving size are illustrative.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 12.5,
                                    color: PlateColors.inkSoft,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (message.hadImage) ...[
                      const SizedBox(height: Space.sm),
                      Text(
                        'The picture from this reply is not kept between sessions.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: Space.sm),
                    _Feedback(message: message),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Rating and reporting, on every generated reply.
///
/// Play requires generated content to be rateable and reportable. The thumbs
/// are the quiet signal; the flag is the one that reaches a person.
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
        _Thumb(
          icon: LucideIcons.thumbsUp,
          label: 'Helpful',
          on: rated == true,
          onTap: rated == null ? () => rate(true) : null,
        ),
        const SizedBox(width: Space.xs),
        _Thumb(
          icon: LucideIcons.thumbsDown,
          label: 'Not helpful',
          on: rated == false,
          onTap: rated == null ? () => rate(false) : null,
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

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 17,
        color: on ? PlateColors.green : PlateColors.inkSoft,
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: PlateCard(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: PlateColors.green),
            ),
            const SizedBox(width: Space.md),
            Text('Reading your plate…', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
      decoration: const BoxDecoration(
        color: PlateColors.cream,
        border: Border(top: BorderSide(color: PlateColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Rice and grilled chicken…',
                counterText: '',
                filled: true,
                fillColor: PlateColors.neutral100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  borderSide: const BorderSide(color: Colors.transparent, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  borderSide: const BorderSide(color: Colors.transparent, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  borderSide: const BorderSide(color: PlateColors.green, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          _SendButton(enabled: !sending, onTap: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send',
      child: Material(
        color: enabled ? PlateColors.green : PlateColors.neutral300,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: const SizedBox(
            width: 52,
            height: 52,
            child: Icon(LucideIcons.arrowUp, color: PlateColors.neutral100, size: 22),
          ),
        ),
      ),
    );
  }
}

/// The row on the meal screen that opens all this. Looks like a composer,
/// behaves like a button — tapping anywhere on it opens the conversation.
class ChatEntryRow extends StatelessWidget {
  const ChatEntryRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Describe your meal in words',
      child: Material(
        color: PlateColors.neutral100,
        borderRadius: BorderRadius.circular(kRadiusSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusSmall),
          onTap: () => ChatScreen.show(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 12, 10, 12),
            child: Row(
              children: [
                Icon(catalogIcon('utensils'), size: 18, color: PlateColors.green),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Describe your meal instead…',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: PlateColors.inkSoft,
                        ),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: PlateColors.green,
                  ),
                  child: const Icon(LucideIcons.arrowUp,
                      size: 18, color: PlateColors.neutral100),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
