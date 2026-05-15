class CardCredentials {
  const CardCredentials({
    required this.cardNumber,
    required this.expiry,
    required this.cvv,
    this.pin = '',
  });

  final String cardNumber;
  final String expiry;
  final String cvv;
  final String pin;

  String get last4 => cardNumber.substring(cardNumber.length - 4);

  String get expiryMonth => expiry.split('/').first.padLeft(2, '0');

  String get expiryYear => '20${expiry.split('/').last.padLeft(2, '0')}';
}
