import 'package:vaultcard/src/domain/models/vault_card.dart';

class ScanResult {
  const ScanResult({
    this.cardNumber,
    this.expiry,
    this.cvv,
    this.network = CardNetwork.unknown,
    this.confidence = 0,
  });

  final String? cardNumber;
  final String? expiry;
  final String? cvv;
  final CardNetwork network;
  final double confidence;
}
