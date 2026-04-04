import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

class CardInput {
  const CardInput({
    required this.cardNumber,
    required this.expiry,
    required this.cvv,
    required this.pin,
    required this.network,
    this.nickname,
  });

  final String cardNumber;
  final String expiry;
  final String cvv;
  final String pin;
  final CardNetwork network;
  final String? nickname;

  CardCredentials get credentials => CardCredentials(
        cardNumber: cardNumber,
        expiry: expiry,
        cvv: cvv,
        pin: pin,
      );
}
