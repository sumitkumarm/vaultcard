import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

class NotificationService {
  const NotificationService.noop();

  static Future<NotificationService> create() async {
    return const NotificationService.noop();
  }

  Future<void> syncForCard(
    VaultCard card,
    NotificationPreferences preferences,
  ) async {}
}
