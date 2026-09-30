import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'settings_store.dart';

/// All app settings as one JSON blob under one key. One read, one write.
/// The plugin is only touched inside load and save, so a platform without it
/// costs the user their settings, not the app's launch.
class PrefsSettingsStore implements SettingsStore {
  PrefsSettingsStore([this._prefs]);

  static const key = 'orion.settings';

  SharedPreferencesAsync? _prefs;

  @override
  Future<AppSettings> load() async {
    try {
      final raw = await _store().getString(key);
      if (raw == null || raw.isEmpty) return const AppSettings();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromJson(json);
    } on Object {
      // Settings in an older shape are not worth a crash on launch.
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      await _store().setString(key, jsonEncode(settings.toJson()));
    } on Object {
      return;
    }
  }

  SharedPreferencesAsync _store() => _prefs ??= SharedPreferencesAsync();
}
