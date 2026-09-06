import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// Everything PlatePatch remembers, kept on the device. No account, no server,
/// nothing to leak — which is also what the Play data-safety form declares.
class PrefsRepository {
  PrefsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kOnboarded = 'onboarded';
  static const _kGoal = 'goal';
  static const _kDietPrefs = 'diet_prefs';
  static const _kHistory = 'history';
  static const _kDeviceToken = 'device_token';

  /// How many saved meals a free user keeps. Older ones are not deleted — they
  /// stay on the device and come back if the user upgrades.
  static const freeSavedLimit = 3;

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;

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
  /// a bad row in local history must never make PlatePatch unlaunchable.
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
