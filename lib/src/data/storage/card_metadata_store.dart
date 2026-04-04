import 'package:vaultcard/src/domain/models/vault_card.dart';

abstract interface class CardMetadataStore {
  Stream<List<VaultCard>> watchCards();
  Future<List<VaultCard>> getCards();
  Future<VaultCard?> getCard(String id);
  Future<void> saveCard(VaultCard card);
  Future<void> deleteCard(String id);
}
