import 'package:vaultcard/src/data/storage/app_preferences_store.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/domain/repositories/settings_repository.dart';

class LocalSettingsRepository implements SettingsRepository {
  const LocalSettingsRepository(this._store);

  final AppPreferencesStore _store;

  @override
  Future<AppSettings> getSettings() => _store.load();

  @override
  Future<void> setOnboardingCompleted() async {
    final settings = await _store.load();
    await _store.save(settings.copyWith(onboardingCompleted: true));
  }

  @override
  Future<void> setAppLockEnabled(bool enabled) async {
    final settings = await _store.load();
    await _store.save(settings.copyWith(appLockEnabled: enabled));
  }

  @override
  Future<void> setAnalyticsEnabled(bool enabled) async {
    final settings = await _store.load();
    await _store.save(settings.copyWith(analyticsEnabled: enabled));
  }

  @override
  Future<void> setSortOption(CardSortOption option) async {
    final settings = await _store.load();
    await _store.save(settings.copyWith(sortOption: option));
  }

  @override
  Future<void> setNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final settings = await _store.load();
    await _store.save(settings.copyWith(notificationPreferences: preferences));
  }
}
