import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaultcard/src/data/storage/app_preferences_store.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';

class SharedPreferencesAppPreferencesStore implements AppPreferencesStore {
  const SharedPreferencesAppPreferencesStore(this._preferences);

  static const _key = 'app_settings';

  final SharedPreferences _preferences;

  @override
  Future<AppSettings> load() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const AppSettings();
    }
    return AppSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_key, jsonEncode(settings.toJson()));
  }
}
