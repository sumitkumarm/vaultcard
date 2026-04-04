import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

class NotificationService {
  const NotificationService();

  Future<void> syncForCard(
    VaultCard card,
    NotificationPreferences preferences,
  ) async {
    // Placeholder for local notification scheduling.
    return;
  }
}
