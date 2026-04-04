import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vaultcard/src/data/repositories/local_card_repository.dart';
import 'package:vaultcard/src/data/storage/card_metadata_store.dart';
import 'package:vaultcard/src/data/storage/secure_credential_store.dart';
import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/card_input.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

void main() {
  test('stores metadata and credentials separately', () async {
    final metadataStore = _FakeCardMetadataStore();
    final secureStore = _FakeSecureCredentialStore();
    final repository = LocalCardRepository(
      metadataStore: metadataStore,
      secureStore: secureStore,
      uuid: const Uuid(),
    );

    final id = await repository.addCard(
      const CardInput(
        cardNumber: '4111111111111111',
        expiry: '06/27',
        cvv: '123',
        pin: '4567',
        network: CardNetwork.visa,
        nickname: 'Travel',
      ),
    );

    final card = await repository.getCard(id);
    final credentials = await repository.getCredentials(id);

    expect(card, isNotNull);
    expect(card!.last4, '1111');
    expect(credentials.pin, '4567');
    expect(metadataStore.cards.single.id, id);
  });

  test('applyBalanceResult updates balance and cooldown', () async {
    final metadataStore = _FakeCardMetadataStore();
    final secureStore = _FakeSecureCredentialStore();
    final repository = LocalCardRepository(
      metadataStore: metadataStore,
      secureStore: secureStore,
      uuid: const Uuid(),
    );

    final id = await repository.addCard(
      const CardInput(
        cardNumber: '4111111111111111',
        expiry: '06/27',
        cvv: '123',
        pin: '4567',
        network: CardNetwork.visa,
      ),
    );

    await repository.applyBalanceResult(
      id,
      BalanceResult(
        balance: 20,
        transactions: const [],
        fetchedAt: DateTime(2026, 4, 4, 12),
      ),
    );

    final card = await repository.getCard(id);
    expect(card!.balance, 20);
    expect(card.refreshBlockedUntil, DateTime(2026, 4, 4, 12, 15));
  });
}

class _FakeCardMetadataStore implements CardMetadataStore {
  final List<VaultCard> cards = [];
  final StreamController<List<VaultCard>> controller =
      StreamController<List<VaultCard>>.broadcast();

  @override
  Future<void> deleteCard(String id) async {
    cards.removeWhere((card) => card.id == id);
    controller.add(List<VaultCard>.from(cards));
  }

  @override
  Future<VaultCard?> getCard(String id) async {
    for (final card in cards) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }

  @override
  Future<List<VaultCard>> getCards() async => List<VaultCard>.from(cards);

  @override
  Future<void> saveCard(VaultCard card) async {
    cards.removeWhere((existing) => existing.id == card.id);
    cards.add(card);
    controller.add(List<VaultCard>.from(cards));
  }

  @override
  Stream<List<VaultCard>> watchCards() => controller.stream;
}

class _FakeSecureCredentialStore implements SecureCredentialStore {
  final Map<String, CardCredentials> data = {};

  @override
  Future<void> delete(String cardId) async {
    data.remove(cardId);
  }

  @override
  Future<CardCredentials> read(String cardId, {required String expiry}) async {
    return data[cardId]!;
  }

  @override
  Future<void> write(String cardId, CardCredentials credentials) async {
    data[cardId] = credentials;
  }
}
