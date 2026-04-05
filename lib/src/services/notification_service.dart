import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/utils/card_utils.dart';

class NotificationService {
  NotificationService._(this._plugin, this._enabled);

  NotificationService.noop()
      : _plugin = FlutterLocalNotificationsPlugin(),
        _enabled = false;

  final FlutterLocalNotificationsPlugin _plugin;
  final bool _enabled;

  static Future<NotificationService> create() async {
    final plugin = FlutterLocalNotificationsPlugin();
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(initializationSettings);
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return NotificationService._(plugin, true);
  }

  Future<void> syncForCard(
    VaultCard card,
    NotificationPreferences preferences,
  ) async {
    if (!_enabled) {
      return;
    }
    if (preferences.lowBalance &&
        card.balance != null &&
        card.balance! < 10 &&
        card.fetchFailureCount == 0) {
      await _plugin.show(
        card.id.hashCode,
        '${card.displayName} is low',
        '${card.displayName} has ${formatCurrency(card.balance!)} remaining.',
        _details,
      );
    }

    if (preferences.refreshFailed && card.fetchFailureCount >= 2) {
      await _plugin.show(
        card.id.hashCode + 1000,
        'Refresh failed',
        'We could not update ${card.displayName}. Open VaultCard to retry.',
        _details,
      );
    }
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'vaultcard_alerts',
      'VaultCard Alerts',
      channelDescription: 'Balance, expiry, and refresh status alerts',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );
}
