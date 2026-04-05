import 'package:vaultcard/src/domain/models/vault_card.dart';

class ScanResult {
  const ScanResult({
    this.cardNumber,
    this.expiry,
    this.cvv,
    this.recognizedText,
    this.network = CardNetwork.unknown,
    this.confidence = 0,
  });

  final String? cardNumber;
  final String? expiry;
  final String? cvv;
  final String? recognizedText;
  final CardNetwork network;
  final double confidence;

  bool get hasCandidateData =>
      cardNumber != null || expiry != null || cvv != null;

  ScanResult copyWith({
    String? cardNumber,
    String? expiry,
    String? cvv,
    String? recognizedText,
    CardNetwork? network,
    double? confidence,
  }) {
    return ScanResult(
      cardNumber: cardNumber ?? this.cardNumber,
      expiry: expiry ?? this.expiry,
      cvv: cvv ?? this.cvv,
      recognizedText: recognizedText ?? this.recognizedText,
      network: network ?? this.network,
      confidence: confidence ?? this.confidence,
    );
  }
}
