import 'package:vaultcard/src/data/storage/app_preferences_store.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';

class InMemoryAppPreferencesStore implements AppPreferencesStore {
  InMemoryAppPreferencesStore([this._settings = const AppSettings()]);

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}
