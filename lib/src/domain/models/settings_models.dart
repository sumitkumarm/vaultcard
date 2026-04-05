import 'package:vaultcard/src/domain/models/vault_card.dart';

class NotificationPreferences {
  const NotificationPreferences({
    this.expiryWarning = true,
    this.lowBalance = true,
    this.balanceUpdated = false,
    this.refreshFailed = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      expiryWarning: json['expiryWarning'] as bool? ?? true,
      lowBalance: json['lowBalance'] as bool? ?? true,
      balanceUpdated: json['balanceUpdated'] as bool? ?? false,
      refreshFailed: json['refreshFailed'] as bool? ?? true,
    );
  }

  final bool expiryWarning;
  final bool lowBalance;
  final bool balanceUpdated;
  final bool refreshFailed;

  NotificationPreferences copyWith({
    bool? expiryWarning,
    bool? lowBalance,
    bool? balanceUpdated,
    bool? refreshFailed,
  }) {
    return NotificationPreferences(
      expiryWarning: expiryWarning ?? this.expiryWarning,
      lowBalance: lowBalance ?? this.lowBalance,
      balanceUpdated: balanceUpdated ?? this.balanceUpdated,
      refreshFailed: refreshFailed ?? this.refreshFailed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'expiryWarning': expiryWarning,
      'lowBalance': lowBalance,
      'balanceUpdated': balanceUpdated,
      'refreshFailed': refreshFailed,
    };
  }
}

class AppSettings {
  const AppSettings({
    this.onboardingCompleted = false,
    this.appLockEnabled = false,
    this.analyticsEnabled = false,
    this.sortOption = CardSortOption.dateAddedNewest,
    this.notificationPreferences = const NotificationPreferences(),
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      appLockEnabled: json['appLockEnabled'] as bool? ?? false,
      analyticsEnabled: json['analyticsEnabled'] as bool? ?? false,
      sortOption: CardSortOption.values.firstWhere(
        (value) => value.name == json['sortOption'],
        orElse: () => CardSortOption.dateAddedNewest,
      ),
      notificationPreferences: NotificationPreferences.fromJson(
        (json['notificationPreferences'] as Map<String, dynamic>? ?? const {}),
      ),
    );
  }

  final bool onboardingCompleted;
  final bool appLockEnabled;
  final bool analyticsEnabled;
  final CardSortOption sortOption;
  final NotificationPreferences notificationPreferences;

  AppSettings copyWith({
    bool? onboardingCompleted,
    bool? appLockEnabled,
    bool? analyticsEnabled,
    CardSortOption? sortOption,
    NotificationPreferences? notificationPreferences,
  }) {
    return AppSettings(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      sortOption: sortOption ?? this.sortOption,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'onboardingCompleted': onboardingCompleted,
      'appLockEnabled': appLockEnabled,
      'analyticsEnabled': analyticsEnabled,
      'sortOption': sortOption.name,
      'notificationPreferences': notificationPreferences.toJson(),
    };
  }
}
