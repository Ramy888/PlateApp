import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Proves the app is a genuine Play install on a genuine device.
///
/// The server verifies the token before spending anything on a model call.
/// Without it, the API is open to anyone with `curl` and the Gemini budget is
/// theirs to spend.
///
/// Every failure returns null rather than throwing. A phone without Play
/// Services, a sideloaded build, or no network are all real situations, and
/// what happens next is the server's decision — not a crash here.
abstract class Attestation {
  /// Returns a token bound to [nonce], or null if one cannot be obtained.
  Future<String?> requestToken(String nonce);
}

class PlayIntegrityAttestation implements Attestation {
  const PlayIntegrityAttestation();

  static const _channel = MethodChannel('com.platepatch.app/integrity');

  @override
  Future<String?> requestToken(String nonce) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('requestToken', {'nonce': nonce});
    } on PlatformException catch (error) {
      // Expected on emulators, sideloaded builds and devices without Play.
      debugPrint('integrity unavailable: ${error.code}');
      return null;
    } on MissingPluginException {
      // Older build of the app shell without the channel wired up.
      return null;
    }
  }
}

/// Used in tests and on platforms with no attestation wired up.
class NoAttestation implements Attestation {
  const NoAttestation({this.token});

  final String? token;

  @override
  Future<String?> requestToken(String nonce) async => token;
}
