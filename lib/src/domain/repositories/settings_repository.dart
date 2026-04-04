import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

abstract interface class SettingsRepository {
  Future<AppSettings> getSettings();
  Future<void> setOnboardingCompleted();
  Future<void> setAppLockEnabled(bool enabled);
  Future<void> setAnalyticsEnabled(bool enabled);
  Future<void> setSortOption(CardSortOption option);
  Future<void> setNotificationPreferences(NotificationPreferences preferences);
}
