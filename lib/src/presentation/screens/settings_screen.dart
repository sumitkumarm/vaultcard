import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).valueOrNull ??
        const AppSettings();
    final notifications = settings.notificationPreferences;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('App Lock'),
            subtitle: const Text(
              'Require biometrics or device passcode to open the app',
            ),
            value: settings.appLockEnabled,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .setAppLockEnabled(value),
          ),
          SwitchListTile(
            title: const Text('Analytics'),
            subtitle: const Text('Disabled by default in MVP'),
            value: settings.analyticsEnabled,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .setAnalyticsEnabled(value),
          ),
          const Divider(),
          _NotificationTile(
            label: 'Expiry warnings',
            value: notifications.expiryWarning,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .updateNotificationPreferences(
                  notifications.copyWith(expiryWarning: value),
                ),
          ),
          _NotificationTile(
            label: 'Low balance alerts',
            value: notifications.lowBalance,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .updateNotificationPreferences(
                  notifications.copyWith(lowBalance: value),
                ),
          ),
          _NotificationTile(
            label: 'Balance updated',
            value: notifications.balanceUpdated,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .updateNotificationPreferences(
                  notifications.copyWith(balanceUpdated: value),
                ),
          ),
          _NotificationTile(
            label: 'Refresh failed',
            value: notifications.refreshFailed,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .updateNotificationPreferences(
                  notifications.copyWith(refreshFailed: value),
                ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
