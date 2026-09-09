import 'package:google_sign_in/google_sign_in.dart';

/// Who is signed in.
///
/// Behind an interface for the same reason purchases and the microphone are:
/// the screens have to be testable without a Google account, and a test that
/// needs a real one is a test nobody runs.
abstract class AuthService {
  /// Signs in, returning the Google ID token the Worker will verify. Null when
  /// the person changed their mind, which is not an error.
  Future<GoogleCredential?> signIn();

  /// Tries to restore a previous session without any UI. Null if there is none.
  Future<GoogleCredential?> restore();

  Future<void> signOut();
}

/// What Google hands back. The token is the only part the server trusts; the
/// rest is here so the app can show who you are while the round trip happens.
class GoogleCredential {
  const GoogleCredential({
    required this.idToken,
    required this.email,
    this.name = '',
    this.photoUrl,
  });

  final String idToken;
  final String email;
  final String name;

  /// Google's own URL. Never stored on our server — it is Google's to serve,
  /// and keeping a copy would buy nothing and add a row to the data-safety
  /// form.
  final String? photoUrl;
}

class GoogleAuthService implements AuthService {
  GoogleAuthService({required this.serverClientId});

  /// The *web* OAuth client. The Android client ids are never referenced in
  /// code — they exist so Google will issue a token to a build signed with a
  /// particular certificate, and nothing more.
  final String serverClientId;

  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _ready = true;
  }

  @override
  Future<GoogleCredential?> signIn() async {
    try {
      await _init();
      if (!GoogleSignIn.instance.supportsAuthenticate()) return null;
      final account = await GoogleSignIn.instance.authenticate();
      return _credential(account);
    } on GoogleSignInException catch (e) {
      // Cancelling is a decision, not a failure — the caller should show
      // nothing at all.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<GoogleCredential?> restore() async {
    try {
      // Initialising is inside the guard on purpose: this runs at launch, and
      // a phone with no Play Services throws from here. A guest opening the
      // app must never see that.
      await _init();
      final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      return account == null ? null : _credential(account);
    } catch (_) {
      // A silent restore that fails silently is the whole point of it.
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // The local session is cleared regardless by the caller.
    }
  }

  GoogleCredential? _credential(GoogleSignInAccount account) {
    final token = account.authentication.idToken;
    if (token == null) return null;
    return GoogleCredential(
      idToken: token,
      email: account.email,
      name: account.displayName ?? '',
      photoUrl: account.photoUrl,
    );
  }
}

/// A permanent guest.
///
/// The same shape as [InertPurchasesService], and for the same reason: a widget
/// test has no platform channels, so reaching for the real one throws from
/// `initialize()`. Screens that are not about signing in take this and stay
/// signed out.
class InertAuthService implements AuthService {
  @override
  Future<GoogleCredential?> signIn() async => null;

  @override
  Future<GoogleCredential?> restore() async => null;

  @override
  Future<void> signOut() async {}
}
