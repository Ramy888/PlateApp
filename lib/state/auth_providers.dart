import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_service.dart';
import '../data/scan_api.dart';
import 'providers.dart';
import 'scan_providers.dart';

/// Who is signed in, as the app sees it.
///
/// The server is the authority — it verified the token and it owns the
/// allowance — so this holds what the server said, not what Google said.
class AuthState {
  const AuthState({this.user, this.photoUrl, this.busy = false, this.problem});

  /// Null for a guest. Everything except the model calls works without one.
  final SignedInUser? user;

  /// Google's own avatar URL, read from the session and never sent to our
  /// server. Gone when the session is.
  final String? photoUrl;

  final bool busy;
  final String? problem;

  bool get isSignedIn => user != null;

  /// The name to greet someone by. Falls back to the part of the email before
  /// the @, because "Good morning, someone@example.com" is nobody's idea of a
  /// greeting.
  String get shortName {
    final name = user?.name.trim() ?? '';
    if (name.isNotEmpty) return name.split(' ').first;
    final email = user?.email ?? '';
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : '';
  }

  AuthState copyWith({
    SignedInUser? user,
    String? photoUrl,
    bool? busy,
    String? problem,
    bool signedOut = false,
    bool clearProblem = false,
  }) =>
      AuthState(
        user: signedOut ? null : (user ?? this.user),
        photoUrl: signedOut ? null : (photoUrl ?? this.photoUrl),
        busy: busy ?? this.busy,
        problem: clearProblem ? null : (problem ?? this.problem),
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthService get _google => ref.read(authServiceProvider);
  ScanApi get _api => ref.read(scanApiProvider);

  /// The silent restore, while it is still running.
  ///
  /// Held rather than fired and forgotten because on Android both this and
  /// [signIn] go through Credential Manager, and starting the second while
  /// the first is in flight stacks two account pickers on top of each other.
  /// It checked `state.busy` and never set it, so nothing actually stopped
  /// that.
  Future<void>? _restoring;

  /// Restores a previous session without any UI, at launch. Silent by design:
  /// a guest should never see anything happen, and a returning user should
  /// simply already be signed in.
  Future<void> restore() {
    if (state.busy || state.isSignedIn) return Future<void>.value();
    return _restoring ??= _restore();
  }

  Future<void> _restore() async {
    try {
      final credential = await _google.restore();
      if (credential == null) return;
      await _exchange(credential);
    } finally {
      _restoring = null;
    }
  }

  /// Returns true if there is now a signed-in account.
  Future<bool> signIn() async {
    // Wait for a restore that is already talking to Credential Manager rather
    // than opening a second conversation beside it. If it succeeds there is
    // nothing left to ask.
    final pending = _restoring;
    if (pending != null) {
      await pending;
      if (state.isSignedIn) return true;
    }
    if (state.busy) return state.isSignedIn;
    state = state.copyWith(busy: true, clearProblem: true);

    try {
      final credential = await _google.signIn();
      if (credential == null) {
        // Cancelled. Not a failure, so nothing is said about it.
        state = state.copyWith(busy: false);
        return false;
      }
      return await _exchange(credential);
    } on SignInProblem catch (problem) {
      // Said as Google explained it, with the tag, so a report from the field
      // names the cause instead of describing the silence.
      state = state.copyWith(
        busy: false,
        problem: '${problem.message} (${problem.code})',
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        busy: false,
        problem: 'Signing in did not work. Try again in a moment.',
      );
      return false;
    }
  }

  Future<bool> _exchange(GoogleCredential credential) async {
    try {
      final device = await ref.read(scanControllerProvider.notifier).deviceToken();
      final user = await _api.signInWithGoogle(
        deviceToken: device,
        idToken: credential.idToken,
      );
      state = AuthState(user: user, photoUrl: credential.photoUrl);
      // The allowance moved to the account, so what the app is showing is now
      // out of date.
      await ref.read(scanControllerProvider.notifier).refreshQuota();
      return true;
    } on ScanFailure catch (failure) {
      state = state.copyWith(busy: false, problem: failure.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        busy: false,
        problem: 'Signing in did not work. Check your connection.',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    final device = ref.read(prefsRepositoryProvider).deviceToken;
    state = const AuthState();
    try {
      await _google.signOut();
      if (device != null) await _api.signOutOfServer(device);
    } catch (_) {
      // Signing out locally is what the person asked for and it has already
      // happened. A dead network must not leave the account's allowance on
      // screen, so the refresh below runs either way.
    } finally {
      await ref.read(scanControllerProvider.notifier).refreshQuota();
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
