import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/services/scan_service.dart';

void main() {
  test('extracts card fields from raw recognized text', () {
    const service = ScanService();
    final result = service.extractFromText(
      'Card 4111 1111 1111 1111 Exp 05/27 CVV 123 PIN 9999',
    );

    expect(result.cardNumber, '4111111111111111');
    expect(result.expiry, '05/27');
    expect(result.cvv, '123');
    expect(result.network, CardNetwork.visa);
  });
}
