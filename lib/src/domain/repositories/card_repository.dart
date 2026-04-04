import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/card_input.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

abstract interface class CardRepository {
  Stream<List<VaultCard>> watchCards();
  Future<List<VaultCard>> getCards();
  Future<VaultCard?> getCard(String id);
  Future<String> addCard(CardInput input);
  Future<void> updateNickname(String id, String nickname);
  Future<void> deleteCard(String id);
  Future<CardCredentials> getCredentials(String id);
  Future<void> applyBalanceResult(String id, BalanceResult result);
  Future<void> markRefreshFailure(String id);
  Future<void> updateRefreshCooldown(String id, DateTime blockedUntil);
}
