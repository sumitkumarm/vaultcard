import 'dart:async';

import 'package:vaultcard/src/data/storage/card_metadata_store.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

class InMemoryCardMetadataStore implements CardMetadataStore {
  final Map<String, VaultCard> _cards = {};
  final StreamController<List<VaultCard>> _controller =
      StreamController<List<VaultCard>>.broadcast();

  @override
  Stream<List<VaultCard>> watchCards() => _controller.stream;

  @override
  Future<List<VaultCard>> getCards() async => _snapshot();

  @override
  Future<VaultCard?> getCard(String id) async => _cards[id];

  @override
  Future<void> saveCard(VaultCard card) async {
    _cards[card.id] = card;
    _emit();
  }

  @override
  Future<void> deleteCard(String id) async {
    _cards.remove(id);
    _emit();
  }

  void _emit() {
    _controller.add(_snapshot());
  }

  List<VaultCard> _snapshot() => List.unmodifiable(_cards.values);
}
