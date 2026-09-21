import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// Everything The Plate remembers about your meals, kept on the device. None of
/// it is uploaded, signed in or not — the account exists to count an allowance,
/// never to sync a history. That is also what the Play data-safety form says.
class PrefsRepository {
  PrefsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kOnboarded = 'onboarded';
  static const _kGoal = 'goal';
  static const _kDietPrefs = 'diet_prefs';
  static const _kHistory = 'history';
  static const _kDeviceToken = 'device_token';
  static const _kChat = 'chat';
  static const _kHasSignedIn = 'has_signed_in';
  static const _kUser = 'signed_in_user';

  /// How many saved meals a free user keeps. Older ones are not deleted — they
  /// stay on the device and come back if the user upgrades.
  static const freeSavedLimit = 3;

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;

  /// Whether an account has ever been signed in on this phone.
  ///
  /// Only used to decide whether to attempt a silent restore at launch.
  /// Attempting one on a phone that has never signed in makes Google offer its
  /// account picker unprompted, as the first thing anyone sees after
  /// installing — which reads as the app demanding a login it does not need.
  bool get hasSignedIn => _prefs.getBool(_kHasSignedIn) ?? false;

  /// Who the server said this device belongs to, last time it said so.
  ///
  /// The session is the device token, not the Google credential — the credential
  /// only establishes it. Google's silent re-auth returns null for its own
  /// reasons, and when it did, the app forgot a session the server still
  /// considered perfectly valid and put a sign-in wall in front of someone who
  /// was signed in. Keeping the verified identity here is what stops that.
  ///
  /// Written from the server's answer, never from Google's unverified claim.
  Map<String, String>? get signedInUser {
    final raw = _prefs.getString(_kUser);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return null;
    }
  }

  Future<void> setSignedInUser(Map<String, String>? user) async {
    if (user == null) {
      await _prefs.remove(_kUser);
    } else {
      await _prefs.setString(_kUser, jsonEncode(user));
    }
  }

  Future<void> setHasSignedIn(bool value) =>
      value ? _prefs.setBool(_kHasSignedIn, true) : _prefs.remove(_kHasSignedIn);

  Future<void> setOnboarded(bool value) => _prefs.setBool(_kOnboarded, value);

  Goal get goal => GoalLabel.fromId(_prefs.getString(_kGoal) ?? Goal.feelSatisfied.id);

  Future<void> setGoal(Goal goal) => _prefs.setString(_kGoal, goal.id);

  Set<DietPref> get dietPrefs => (_prefs.getStringList(_kDietPrefs) ?? const [])
      .map(DietPrefLabel.fromId)
      .whereType<DietPref>()
      .toSet();

  Future<void> setDietPrefs(Set<DietPref> prefs) =>
      _prefs.setStringList(_kDietPrefs, prefs.map((p) => p.id).toList());

  /// Newest first. Corrupt entries are dropped rather than crashing the app —
  /// a bad row in local history must never make The Plate unlaunchable.
  List<SavedPatch> get history {
    final raw = _prefs.getStringList(_kHistory) ?? const [];
    final out = <SavedPatch>[];
    for (final row in raw) {
      try {
        out.add(SavedPatch.fromJson(jsonDecode(row) as Map<String, dynamic>));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  /// The chat transcript, oldest first. Words only — a reply's picture lives
  /// in memory for the session and is deliberately not written to disk, since
  /// the server deletes its copy within a day anyway.
  List<String> get chatJson => _prefs.getStringList(_kChat) ?? const [];

  Future<void> setChatJson(List<String> rows) => _prefs.setStringList(_kChat, rows);

  Future<void> setHistory(List<SavedPatch> history) => _prefs.setStringList(
        _kHistory,
        history.map((h) => jsonEncode(h.toJson())).toList(),
      );

  /// The anonymous device token issued by the scan API. Not an account: there
  /// is nothing to sign into and it identifies a quota, not a person.
  String? get deviceToken {
    final value = _prefs.getString(_kDeviceToken);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> setDeviceToken(String? token) => token == null
      ? _prefs.remove(_kDeviceToken)
      : _prefs.setString(_kDeviceToken, token);

  static Future<PrefsRepository> open() async =>
      PrefsRepository(await SharedPreferences.getInstance());
}
