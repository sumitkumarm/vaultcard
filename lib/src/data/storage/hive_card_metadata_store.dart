import 'dart:async';

import 'package:hive/hive.dart';
import 'package:vaultcard/src/data/storage/card_metadata_store.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

class HiveCardMetadataStore implements CardMetadataStore {
  HiveCardMetadataStore._(this._box);

  static const _boxName = 'vault_cards';

  final Box<Map<dynamic, dynamic>> _box;
  final StreamController<List<VaultCard>> _controller =
      StreamController<List<VaultCard>>.broadcast();

  static Future<HiveCardMetadataStore> create() async {
    final box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
    final store = HiveCardMetadataStore._(box);
    box.watch().listen((_) => store._emit());
    store._emit();
    return store;
  }

  void _emit() {
    _controller.add(_decodeCards());
  }

  List<VaultCard> _decodeCards() {
    return _box.values
        .map((value) => VaultCard.fromJson(Map<dynamic, dynamic>.from(value)))
        .toList();
  }

  @override
  Stream<List<VaultCard>> watchCards() => _controller.stream;

  @override
  Future<List<VaultCard>> getCards() async => _decodeCards();

  @override
  Future<VaultCard?> getCard(String id) async {
    final value = _box.get(id);
    if (value == null) {
      return null;
    }
    return VaultCard.fromJson(Map<dynamic, dynamic>.from(value));
  }

  @override
  Future<void> saveCard(VaultCard card) async {
    await _box.put(card.id, card.toJson());
    _emit();
  }

  @override
  Future<void> deleteCard(String id) async {
    await _box.delete(id);
    _emit();
  }
}
