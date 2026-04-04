import 'package:vaultcard/src/domain/models/settings_models.dart';

abstract interface class AppPreferencesStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}
