import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/utils/card_utils.dart';

void main() {
  group('inferNetwork', () {
    test('detects visa', () {
      expect(inferNetwork('4111111111111111'), CardNetwork.visa);
    });

    test('detects mastercard 51 range', () {
      expect(inferNetwork('5555555555554444'), CardNetwork.mastercard);
    });

    test('detects mastercard 2-series range', () {
      expect(inferNetwork('2221000000000009'), CardNetwork.mastercard);
    });
  });

  group('isValidCardNumber', () {
    test('accepts valid supported network numbers', () {
      expect(isValidCardNumber('4111 1111 1111 1111'), isTrue);
      expect(isValidCardNumber('5555 5555 5555 4444'), isTrue);
    });

    test('rejects unsupported or failed checksum numbers', () {
      expect(isValidCardNumber('371449635398431'), isFalse);
      expect(isValidCardNumber('4111111111111112'), isFalse);
    });
  });

  test('sortCards sorts by highest balance', () {
    final cards = [
      VaultCard(
        id: '1',
        network: CardNetwork.visa,
        last4: '1111',
        expiry: '12/26',
        addedAt: DateTime(2026, 1, 1),
        balance: 10,
      ),
      VaultCard(
        id: '2',
        network: CardNetwork.mastercard,
        last4: '2222',
        expiry: '11/26',
        addedAt: DateTime(2026, 1, 2),
        balance: 30,
      ),
    ];

    final result = sortCards(cards, CardSortOption.balanceHighToLow);
    expect(result.first.id, '2');
  });
}
