import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:vaultcard/src/data/storage/card_metadata_store.dart';
import 'package:vaultcard/src/data/storage/secure_credential_store.dart';
import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/card_input.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/domain/repositories/card_repository.dart';

class LocalCardRepository implements CardRepository {
  LocalCardRepository({
    required CardMetadataStore metadataStore,
    required SecureCredentialStore secureStore,
    Uuid? uuid,
  })  : _metadataStore = metadataStore,
        _secureStore = secureStore,
        _uuid = uuid ?? const Uuid();

  final CardMetadataStore _metadataStore;
  final SecureCredentialStore _secureStore;
  final Uuid _uuid;

  @override
  Stream<List<VaultCard>> watchCards() => _metadataStore.watchCards();

  @override
  Future<List<VaultCard>> getCards() => _metadataStore.getCards();

  @override
  Future<VaultCard?> getCard(String id) => _metadataStore.getCard(id);

  @override
  Future<String> addCard(CardInput input) async {
    final id = _uuid.v4();
    final card = VaultCard(
      id: id,
      nickname: input.nickname?.trim().isEmpty == true ? null : input.nickname,
      network: input.network,
      last4: input.cardNumber.substring(input.cardNumber.length - 4),
      expiry: input.expiry,
      addedAt: DateTime.now(),
    );
    await _secureStore.write(id, input.credentials);
    await _metadataStore.saveCard(card);
    return id;
  }

  @override
  Future<void> updateNickname(String id, String nickname) async {
    final card = await getCard(id);
    if (card == null) {
      return;
    }
    await _metadataStore.saveCard(
      card.copyWith(nickname: nickname.trim().isEmpty ? null : nickname.trim()),
    );
  }

  @override
  Future<void> deleteCard(String id) async {
    await _secureStore.delete(id);
    await _metadataStore.deleteCard(id);
  }

  @override
  Future<CardCredentials> getCredentials(String id) async {
    final card = await getCard(id);
    if (card == null) {
      throw StateError('Card not found: $id');
    }
    return _secureStore.read(id, expiry: card.expiry);
  }

  @override
  Future<void> applyBalanceResult(String id, BalanceResult result) async {
    final card = await getCard(id);
    if (card == null) {
      return;
    }
    await _metadataStore.saveCard(
      card.copyWith(
        balance: result.balance,
        transactions: result.transactions,
        lastFetchedAt: result.fetchedAt,
        fetchFailureCount: 0,
        refreshBlockedUntil: result.fetchedAt.add(const Duration(minutes: 15)),
      ),
    );
  }

  @override
  Future<void> markRefreshFailure(String id) async {
    final card = await getCard(id);
    if (card == null) {
      return;
    }
    await _metadataStore.saveCard(
      card.copyWith(
        fetchFailureCount: card.fetchFailureCount + 1,
      ),
    );
  }

  @override
  Future<void> updateRefreshCooldown(String id, DateTime blockedUntil) async {
    final card = await getCard(id);
    if (card == null) {
      return;
    }
    await _metadataStore.saveCard(
      card.copyWith(refreshBlockedUntil: blockedUntil),
    );
  }
}
