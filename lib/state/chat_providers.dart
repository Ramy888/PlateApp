import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../data/scan_api.dart';
import '../data/voice_service.dart';
import 'providers.dart';
import 'scan_providers.dart';

/// Who said it.
enum ChatAuthor { user, assistant }

/// One line of the conversation.
///
/// The words persist; a picture does not. The server deletes its copy within a
/// day, so writing image bytes to the phone would only create a second thing to
/// promise about and then have to delete.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.sentAt,
    this.additionId = '',
    this.foodIds = const [],
    this.hadImage = false,
    this.rating,
    this.image,
    this.failed = false,
    this.spoken = false,
  });

  final String id;
  final ChatAuthor author;
  final String text;
  final DateTime sentAt;

  /// Catalogue ids the server matched, already checked against its closed set.
  final String additionId;
  final List<String> foodIds;

  /// Whether a picture came with this reply, even if it is no longer in memory.
  final bool hadImage;

  /// True for a thumb up, false for down, null for not yet said.
  final bool? rating;

  /// Held for this session only, never written to disk.
  final Uint8List? image;

  /// A reply that could not be produced. Kept in the list so the conversation
  /// still reads, rather than vanishing mid-thread.
  final bool failed;

  /// True where the user said it rather than typed it, so the thread can show
  /// that this line is a transcript and might have been misheard.
  final bool spoken;

  bool get isUser => author == ChatAuthor.user;

  ChatMessage copyWith({bool? rating, Uint8List? image}) => ChatMessage(
        id: id,
        author: author,
        text: text,
        sentAt: sentAt,
        additionId: additionId,
        foodIds: foodIds,
        hadImage: hadImage,
        rating: rating ?? this.rating,
        image: image ?? this.image,
        failed: failed,
        spoken: spoken,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author.name,
        'text': text,
        'sentAt': sentAt.toIso8601String(),
        if (additionId.isNotEmpty) 'additionId': additionId,
        if (foodIds.isNotEmpty) 'foodIds': foodIds,
        if (hadImage) 'hadImage': true,
        if (rating != null) 'rating': rating,
        if (failed) 'failed': true,
        if (spoken) 'spoken': true,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        author: json['author'] == 'user' ? ChatAuthor.user : ChatAuthor.assistant,
        text: json['text'] as String? ?? '',
        sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
        additionId: json['additionId'] as String? ?? '',
        foodIds:
            ((json['foodIds'] as List?) ?? const []).whereType<String>().toList(growable: false),
        hadImage: json['hadImage'] as bool? ?? false,
        rating: json['rating'] as bool?,
        failed: json['failed'] as bool? ?? false,
        spoken: json['spoken'] as bool? ?? false,
      );
}

class ChatState {
  const ChatState({this.messages = const [], this.sending = false, this.problem});

  /// Oldest first.
  final List<ChatMessage> messages;
  final bool sending;

  /// Something to say out loud, above the composer.
  final String? problem;

  bool get isEmpty => messages.isEmpty;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    String? problem,
    bool clearProblem = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        problem: clearProblem ? null : (problem ?? this.problem),
      );
}

/// The conversation.
///
/// Held on the phone, like everything else in this app. The Worker keeps an id
/// and a thumb so a bad reply can be acted on; it never sees the transcript
/// again after the turn that produced it.
class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    final rows = ref.read(prefsRepositoryProvider).chatJson;
    final messages = <ChatMessage>[];
    for (final row in rows) {
      try {
        messages.add(ChatMessage.fromJson(jsonDecode(row) as Map<String, dynamic>));
      } catch (_) {
        // A corrupt row is dropped, never a crash — the same rule the saved
        // patch history follows.
      }
    }
    return ChatState(messages: messages);
  }

  ScanApi get _api => ref.read(scanApiProvider);

  Future<void> _persist(List<ChatMessage> messages) => ref
      .read(prefsRepositoryProvider)
      .setChatJson(messages.map((m) => jsonEncode(m.toJson())).toList(growable: false));

  /// A spoken turn, appended to the same conversation a typed one goes in.
  ///
  /// One thread, whichever way the words arrived — a history split by input
  /// method would be a filing decision the user never asked to make.
  Future<void> sendClip(VoiceClip clip) async {
    if (state.sending) return;
    state = state.copyWith(sending: true, clearProblem: true);

    try {
      final token = await ref.read(scanControllerProvider.notifier).deviceToken();
      final settings = ref.read(settingsProvider);
      final reply = await _api.voice(
        deviceToken: token,
        audio: clip.bytes,
        mimeType: clip.mimeType,
        avoid: settings.dietPrefs.map((p) => p.id).toSet(),
        goal: settings.goal.id,
      );

      // What was heard goes in as the user's line, so the thread reads the same
      // as a typed one and the transcript can be checked before it is trusted.
      final heard = reply.transcript.trim();
      var messages = [
        ...state.messages,
        ChatMessage(
          id: 'v${DateTime.now().microsecondsSinceEpoch}',
          author: ChatAuthor.user,
          text: heard.isEmpty ? '(nothing was caught)' : heard,
          sentAt: DateTime.now(),
          spoken: true,
        ),
      ];

      Uint8List? image;
      if (reply.imageUrl != null) {
        try {
          image = await _api.previewImage(deviceToken: token, url: reply.imageUrl!);
        } catch (_) {
          // The words are the product.
        }
      }

      messages = [
        ...messages,
        ChatMessage(
          id: reply.messageId,
          author: ChatAuthor.assistant,
          text: reply.reply,
          sentAt: DateTime.now(),
          additionId: reply.additionId,
          foodIds: reply.foodIds,
          hadImage: image != null,
          image: image,
        ),
      ];
      state = state.copyWith(messages: messages, sending: false);
      await _persist(messages);
      ref.read(scanControllerProvider.notifier).noteQuota(reply.quota);
    } on ScanFailure catch (failure) {
      state = state.copyWith(sending: false, problem: failure.message);
      if (failure.error.suggestsUpgrade) _upgrade = failure.error;
    } catch (_) {
      state = state.copyWith(
        sending: false,
        problem: 'That could not be sent. Check your connection.',
      );
    }
  }

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) return;

    final mine = ChatMessage(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      author: ChatAuthor.user,
      text: message,
      sentAt: DateTime.now(),
    );
    var messages = [...state.messages, mine];
    state = state.copyWith(messages: messages, sending: true, clearProblem: true);
    await _persist(messages);

    try {
      // Registration is lazy everywhere else in the app, and chatting is the
      // first network call some people will make.
      final token = await ref.read(scanControllerProvider.notifier).deviceToken();
      final settings = ref.read(settingsProvider);
      final reply = await _api.chat(
        deviceToken: token,
        message: message,
        avoid: settings.dietPrefs.map((p) => p.id).toSet(),
        goal: settings.goal.id,
      );

      Uint8List? image;
      if (reply.imageUrl != null) {
        try {
          image = await _api.previewImage(deviceToken: token, url: reply.imageUrl!);
        } catch (_) {
          // The words are the product. A picture that will not download is a
          // missing picture, not a failed turn.
        }
      }

      messages = [
        ...messages,
        ChatMessage(
          id: reply.messageId,
          author: ChatAuthor.assistant,
          text: reply.reply,
          sentAt: DateTime.now(),
          additionId: reply.additionId,
          foodIds: reply.foodIds,
          hadImage: image != null,
          image: image,
        ),
      ];
      state = state.copyWith(messages: messages, sending: false);
      await _persist(messages);
      ref.read(scanControllerProvider.notifier).noteQuota(reply.quota);
    } on ScanFailure catch (failure) {
      messages = [
        ...messages,
        ChatMessage(
          id: 'e${DateTime.now().microsecondsSinceEpoch}',
          author: ChatAuthor.assistant,
          text: failure.message,
          sentAt: DateTime.now(),
          failed: true,
        ),
      ];
      state = state.copyWith(messages: messages, sending: false, problem: failure.message);
      await _persist(messages);
      if (failure.error.suggestsUpgrade) _upgrade = failure.error;
    } catch (_) {
      state = state.copyWith(
        sending: false,
        problem: 'That could not be sent. Check your connection.',
      );
    }
  }

  /// Set when the last turn ran out of allowance, so the screen can show the
  /// paywall instead of an error. Read once and cleared.
  ScanError? _upgrade;

  ScanError? takeUpgrade() {
    final value = _upgrade;
    _upgrade = null;
    return value;
  }

  Future<void> rate(ChatMessage message, {required bool helpful}) async {
    final messages = state.messages
        .map((m) => m.id == message.id ? m.copyWith(rating: helpful) : m)
        .toList(growable: false);
    state = state.copyWith(messages: messages);
    await _persist(messages);

    final token = ref.read(prefsRepositoryProvider).deviceToken;
    if (token == null || message.id.isEmpty) return;
    await _api.rate(deviceToken: token, messageId: message.id, helpful: helpful);
  }

  Future<void> clear() async {
    state = const ChatState();
    await _persist(const []);
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);
