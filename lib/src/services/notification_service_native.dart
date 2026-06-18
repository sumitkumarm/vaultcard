import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

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
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
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

    if (preferences.expiryWarning) {
      await _scheduleExpiryNotifications(card);
    }
  }

  Future<void> _scheduleExpiryNotifications(VaultCard card) async {
    final expiryDate = _resolveExpiryDate(card.expiry);
    if (expiryDate == null) {
      return;
    }

    await _scheduleIfFuture(
      id: card.id.hashCode + 2000,
      scheduledAt: expiryDate.subtract(const Duration(days: 30)),
      title: '${card.displayName} expires soon',
      body:
          '${card.displayName} expires on ${card.expiry}. Use it before it expires.',
    );
    await _scheduleIfFuture(
      id: card.id.hashCode + 2001,
      scheduledAt: expiryDate.subtract(const Duration(days: 7)),
      title: '${card.displayName} expires soon',
      body:
          '${card.displayName} expires on ${card.expiry}. Use it before it expires.',
    );
  }

  Future<void> _scheduleIfFuture({
    required int id,
    required DateTime scheduledAt,
    required String title,
    required String body,
  }) async {
    if (scheduledAt.isBefore(DateTime.now())) {
      return;
    }
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledAt, tz.local),
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  DateTime? _resolveExpiryDate(String expiry) {
    final parts = expiry.split('/');
    if (parts.length != 2) {
      return null;
    }
    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);
    if (month == null || year == null) {
      return null;
    }
    final fullYear = 2000 + year;
    return DateTime(fullYear, month + 1, 0, 12);
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
