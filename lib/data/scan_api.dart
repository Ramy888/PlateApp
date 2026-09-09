import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Talks to The Plate Worker.
///
/// The Gemini key is never here — the app has no credential worth stealing.
/// Every failure is turned into something the UI can say out loud, because the
/// answer to "recognition did not work" is always "build the meal by hand",
/// never a dead end.
class ScanApi {
  ScanApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Where the API lives. Overridable at build time so a debug build can point
  /// at a local `wrangler dev`.
  static const defaultBaseUrl = String.fromEnvironment(
    'PLATEPATCH_API',
    defaultValue: 'https://platepatch-api.ramy-comm.workers.dev',
  );

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Asks for a single-use nonce to bind an integrity token to. Without one,
  /// a captured token could be replayed forever.
  Future<String> challenge() async {
    final response = await _send(
      () => _client.post(_uri('/v1/challenge'), headers: const {}),
    );
    return _decode(response)['nonce'] as String;
  }

  /// Registers this install. Called once; the token is kept in local storage.
  Future<DeviceRegistration> registerDevice({
    required String platform,
    String? integrityToken,
    String? rcUserId,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/v1/device'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'platform': platform,
          'integrityToken': ?integrityToken,
          'rcUserId': ?rcUserId,
        }),
      ),
    );
    final body = _decode(response);
    return DeviceRegistration(
      token: body['deviceToken'] as String,
      quota: ScanQuota.fromJson(body['quota'] as Map<String, dynamic>),
    );
  }

  Future<ScanQuota> quota(String deviceToken) async {
    final response = await _send(
      () => _client.get(_uri('/v1/quota'), headers: _auth(deviceToken)),
    );
    return ScanQuota.fromJson(_decode(response));
  }

  /// Sends one already-processed photo for recognition.
  Future<ScanResponse> scan({
    required String deviceToken,
    required Uint8List jpeg,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/v1/scan'))
      ..headers.addAll(_auth(deviceToken))
      // No explicit content type: the filename is enough, and the Worker
      // defaults an untyped part to image/jpeg.
      ..files.add(http.MultipartFile.fromBytes('image', jpeg, filename: 'meal.jpg'));

    final response = await _send(() async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    });
    return ScanResponse.fromJson(_decode(response));
  }

  /// Generates a visual preview of the meal with one addition.
  ///
  /// Sends the addition's **id**, never its name: the server looks the phrase
  /// up in a closed set, so nothing a client sends can reach an image prompt.
  Future<PreviewResult> preview({
    required String deviceToken,
    required Uint8List jpeg,
    required String additionId,
    String? scanId,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/v1/preview'))
      ..headers.addAll(_auth(deviceToken))
      ..fields['additionId'] = additionId
      ..files.add(http.MultipartFile.fromBytes('image', jpeg, filename: 'meal.jpg'));
    if (scanId != null) request.fields['scanId'] = scanId;

    final response = await _send(() async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }, timeout: const Duration(seconds: 120));
    return PreviewResult.fromJson(_decode(response));
  }

  /// Signs this device into a Google account. The server verifies the token
  /// against Google's own keys; the app never claims an identity, it only
  /// forwards one.
  Future<SignedInUser> signInWithGoogle({
    required String deviceToken,
    required String idToken,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/v1/auth/google'),
        headers: {..._auth(deviceToken), 'content-type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      ),
      timeout: const Duration(seconds: 30),
    );
    return SignedInUser.fromJson(_decode(response));
  }

  /// Ends the session on this device. The account and its allowance survive.
  Future<void> signOutOfServer(String deviceToken) async {
    try {
      await _send(
        () => _client.post(_uri('/v1/auth/signout'), headers: _auth(deviceToken)),
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // Signing out must never fail in front of someone who is leaving.
    }
  }

  /// One chat turn: what the user typed goes up, words and a picture come back.
  ///
  /// The message is the only free text this app ever sends. The Worker answers
  /// with catalogue ids rather than echoing it into an image prompt, which is
  /// what stops a typed sentence from steering the picture model.
  Future<ChatReply> chat({
    required String deviceToken,
    required String message,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/v1/chat'),
        headers: {..._auth(deviceToken), 'content-type': 'application/json'},
        body: jsonEncode({'message': message}),
      ),
      // Two model calls in series, one of them drawing an image.
      timeout: const Duration(seconds: 120),
    );
    return ChatReply.fromJson(_decode(response));
  }

  /// A spoken turn. The recording goes up, the transcript and the same answer
  /// a typed message gets come back.
  Future<ChatReply> voice({
    required String deviceToken,
    required Uint8List audio,
    required String mimeType,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/v1/voice'))
      ..headers.addAll(_auth(deviceToken))
      ..files.add(http.MultipartFile.fromBytes(
        'audio',
        audio,
        filename: 'meal.m4a',
        contentType: MediaType.parse(mimeType),
      ));

    final response = await _send(() async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }, timeout: const Duration(seconds: 120));
    return ChatReply.fromJson(_decode(response));
  }

  /// Writes up and draws a plate the user built by hand.
  ///
  /// Sends ids, never words. The engine on the phone has already chosen the
  /// addition; this is asking for a sentence and a picture of that decision.
  Future<ChatReply> plate({
    required String deviceToken,
    required List<String> foodIds,
    required String additionId,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('/v1/plate'),
        headers: {..._auth(deviceToken), 'content-type': 'application/json'},
        body: jsonEncode({'foodIds': foodIds, 'additionId': additionId}),
      ),
      timeout: const Duration(seconds: 90),
    );
    return ChatReply.fromJson(_decode(response));
  }

  /// Records how a generated reply landed. Play requires generated content to
  /// be rateable; like `report`, it must never fail in front of the user.
  Future<void> rate({
    required String deviceToken,
    required String messageId,
    required bool helpful,
  }) async {
    try {
      await _send(
        () => _client.post(
          _uri('/v1/rating'),
          headers: {..._auth(deviceToken), 'content-type': 'application/json'},
          body: jsonEncode({
            'messageId': messageId,
            'rating': helpful ? 'up' : 'down',
          }),
        ),
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // A thumb is a nicety. Losing one is not worth an error in front of
      // someone who was trying to be helpful.
    }
  }

  /// Downloads a generated preview. Kept on the device only.
  Future<Uint8List> previewImage({
    required String deviceToken,
    required String url,
  }) async {
    final response = await _send(
      () => _client.get(Uri.parse(url), headers: _auth(deviceToken)),
      timeout: const Duration(seconds: 60),
    );
    if (response.statusCode != 200) {
      throw const ScanFailure(ScanError.unknown, 'That preview could not be loaded.');
    }
    return response.bodyBytes;
  }

  /// Files a report against an AI result. Required by Google Play, and it must
  /// never fail in front of the user — so this swallows everything.
  Future<void> report({
    required String deviceToken,
    required String targetType,
    required String targetId,
    required String reason,
    String? note,
  }) async {
    try {
      await _client
          .post(
            _uri('/v1/report'),
            headers: {..._auth(deviceToken), 'content-type': 'application/json'},
            body: jsonEncode({
              'targetType': targetType,
              'targetId': targetId,
              'reason': reason,
              if (note != null && note.isNotEmpty) 'note': note,
            }),
          )
          .timeout(timeout);
    } catch (_) {
      // Reporting something offensive must not itself produce an error.
    }
  }

  /// Backs the "delete my data" promise with a real call.
  Future<void> forgetDevice(String deviceToken) async {
    await _send(() => _client.delete(_uri('/v1/device'), headers: _auth(deviceToken)));
  }

  Map<String, String> _auth(String token) => {'authorization': 'Bearer $token'};

  Future<http.Response> _send(
    Future<http.Response> Function() run, {
    Duration? timeout,
  }) async {
    try {
      return await run().timeout(timeout ?? this.timeout);
    } on ScanFailure {
      rethrow;
    } catch (_) {
      throw const ScanFailure(
        ScanError.offline,
        'No connection. You can still build the meal by hand.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    final code = body['error'] as String? ?? '';
    final message = body['message'] as String? ??
        'Something went wrong. You can still build the meal by hand.';
    throw ScanFailure(ScanError.fromCode(code, response.statusCode), message);
  }

  void close() => _client.close();
}

enum ScanError {
  offline,
  quotaExhausted,
  trialEnded,
  noFoodFound,
  notAMeal,
  busy,
  rateLimited,
  unauthorized,

  /// A guest asked for something only an account can have. Not an error to
  /// apologise for — an invitation.
  signInRequired,

  /// The sign-in itself could not be verified.
  signInFailed,
  attestationFailed,
  imageRejected,
  previewExpired,
  unknown;

  static ScanError fromCode(String code, int status) => switch (code) {
        'quota_exhausted' => ScanError.quotaExhausted,
        'trial_ended' => ScanError.trialEnded,
        'no_food_found' => ScanError.noFoodFound,
        'not_a_meal' || 'preview_blocked' => ScanError.notAMeal,
        'preview_unavailable' => ScanError.busy,
        'preview_expired' => ScanError.previewExpired,
        'invalid_addition' || 'invalid_food' => ScanError.imageRejected,
        'sign_in_required' => ScanError.signInRequired,
        'invalid_token' || 'token_expired' => ScanError.signInFailed,
        'sign_in_unavailable' => ScanError.busy,
        'chat_unavailable' => ScanError.busy,
        'missing_audio' || 'audio_too_large' => ScanError.imageRejected,
        'chat_blocked' => ScanError.notAMeal,
        'empty_message' || 'invalid_field' => ScanError.imageRejected,
        'recognition_busy' => ScanError.busy,
        'rate_limited' => ScanError.rateLimited,
        'unknown_device' || 'unauthorized' => ScanError.unauthorized,
        'attestation_failed' => ScanError.attestationFailed,
        'image_too_large' ||
        'unsupported_type' ||
        'missing_image' ||
        'empty_image' =>
          ScanError.imageRejected,
        _ => status == 429 ? ScanError.rateLimited : ScanError.unknown,
      };

  /// Whether the user can usefully try the same thing again.
  bool get isRetryable =>
      this == ScanError.busy || this == ScanError.offline || this == ScanError.unknown;

  /// Whether this is a reason to offer sign-in rather than an error.
  bool get needsSignIn =>
      this == ScanError.signInRequired || this == ScanError.signInFailed;

  /// Whether this is a reason to show the paywall rather than an error.
  bool get suggestsUpgrade =>
      this == ScanError.quotaExhausted || this == ScanError.trialEnded;

  /// The trial running out is the moment to sell, not an error to apologise for.
  bool get isTrialEnded => this == ScanError.trialEnded;
}

class ScanFailure implements Exception {
  const ScanFailure(this.error, this.message);

  final ScanError error;
  final String message;

  @override
  String toString() => 'ScanFailure(${error.name}: $message)';
}

class DeviceRegistration {
  const DeviceRegistration({required this.token, required this.quota});

  final String token;
  final ScanQuota quota;
}

class ScanQuota {
  const ScanQuota({
    required this.scans,
    required this.previews,
    required this.resetsAt,
    required this.pro,
    this.trialActive = false,
    this.trialDaysLeft = 0,
  });

  final int scans;
  final int previews;
  final DateTime resetsAt;
  final bool pro;
  final bool trialActive;
  final int trialDaysLeft;

  /// Before the device has ever registered.
  static final unknown = ScanQuota(
    scans: 0,
    previews: 0,
    resetsAt: DateTime.fromMillisecondsSinceEpoch(0),
    pro: false,
  );

  bool get hasScans => scans > 0;

  factory ScanQuota.fromJson(Map<String, dynamic> json) => ScanQuota(
        scans: (json['scans'] as num?)?.toInt() ?? 0,
        previews: (json['previews'] as num?)?.toInt() ?? 0,
        resetsAt: DateTime.fromMillisecondsSinceEpoch(
          ((json['resetsAt'] as num?)?.toInt() ?? 0) * 1000,
        ),
        pro: json['pro'] as bool? ?? false,
        trialActive: json['trialActive'] as bool? ?? false,
        trialDaysLeft: (json['trialDaysLeft'] as num?)?.toInt() ?? 0,
      );
}

/// A generated preview, and the label that must travel with it.
class PreviewResult {
  const PreviewResult({
    required this.url,
    required this.disclaimer,
    required this.quota,
  });

  final String url;

  /// Shown with the image, always. Never dismissible.
  final String disclaimer;
  final ScanQuota quota;

  factory PreviewResult.fromJson(Map<String, dynamic> json) => PreviewResult(
        url: json['previewUrl'] as String? ?? '',
        disclaimer: json['disclaimer'] as String? ??
            'AI visual preview — appearance and serving size are illustrative.',
        quota: ScanQuota.fromJson((json['quota'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

/// Who the server believes is signed in on this device.
class SignedInUser {
  const SignedInUser({required this.id, required this.email, required this.name});

  /// Google's per-app subject id. Opaque, and the only thing an allowance is
  /// keyed on.
  final String id;
  final String email;
  final String name;

  factory SignedInUser.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SignedInUser(
      id: user['id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      name: user['name'] as String? ?? '',
    );
  }
}

/// One reply from the meal assistant.
///
/// `foodIds` and `additionId` are catalogue ids the server has already checked
/// against its own closed set, so the app can look them up without validating
/// them again.
class ChatReply {
  const ChatReply({
    required this.messageId,
    required this.reply,
    required this.foodIds,
    required this.additionId,
    this.transcript = '',
    required this.imageUrl,
    required this.disclaimer,
    required this.quota,
  });

  /// What a rating or a report is filed against.
  final String messageId;
  final String reply;
  final List<String> foodIds;

  /// Empty when the model could not choose one, which also means no picture.
  final String additionId;

  /// What the model heard. Empty for a typed turn.
  final String transcript;

  /// Null when the picture could not be drawn. The words still stand.
  final String? imageUrl;

  /// Shown with the image, always. Never dismissible.
  final String disclaimer;
  final ScanQuota quota;

  factory ChatReply.fromJson(Map<String, dynamic> json) => ChatReply(
        messageId: json['messageId'] as String? ?? '',
        reply: json['reply'] as String? ?? '',
        foodIds: ((json['foodIds'] as List?) ?? const [])
            .whereType<String>()
            .toList(growable: false),
        additionId: json['additionId'] as String? ?? '',
        transcript: json['transcript'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        disclaimer: json['disclaimer'] as String? ??
            'AI visual preview — appearance and serving size are illustrative.',
        quota: ScanQuota.fromJson((json['quota'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

/// What one scan produced. `foods` are raw model labels; matching them onto the
/// catalogue happens on the device, in [FoodMatcher].
class ScanResponse {
  const ScanResponse({
    required this.scanId,
    required this.foods,
    required this.components,
    required this.quota,
  });

  final String scanId;
  final List<({String name, double confidence})> foods;
  final MealComponents components;
  final ScanQuota quota;

  factory ScanResponse.fromJson(Map<String, dynamic> json) => ScanResponse(
        scanId: json['scanId'] as String? ?? '',
        foods: ((json['foods'] as List?) ?? const [])
            .map((f) => (
                  name: (f as Map<String, dynamic>)['name'] as String? ?? '',
                  confidence: ((f['confidence'] as num?) ?? 0).toDouble(),
                ))
            .where((f) => f.name.isNotEmpty)
            .toList(),
        components:
            MealComponents.fromJson((json['components'] as Map?)?.cast<String, dynamic>() ?? const {}),
        quota: ScanQuota.fromJson((json['quota'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

/// What the model could and could not see. Advisory only — the rule engine
/// still decides everything from the confirmed food list.
class MealComponents {
  const MealComponents({
    required this.protein,
    required this.fibre,
    required this.healthyFat,
  });

  final ComponentPresence protein;
  final ComponentPresence fibre;
  final ComponentPresence healthyFat;

  factory MealComponents.fromJson(Map<String, dynamic> json) => MealComponents(
        protein: ComponentPresence.fromId(json['protein'] as String?),
        fibre: ComponentPresence.fromId(json['fibre'] as String?),
        healthyFat: ComponentPresence.fromId(json['healthyFat'] as String?),
      );
}

enum ComponentPresence {
  present,
  possiblyMissing,
  uncertain;

  static ComponentPresence fromId(String? id) => switch (id) {
        'present' => ComponentPresence.present,
        'possibly_missing' => ComponentPresence.possiblyMissing,
        _ => ComponentPresence.uncertain,
      };
}
