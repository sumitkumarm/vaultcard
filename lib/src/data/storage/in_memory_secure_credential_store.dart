import 'package:vaultcard/src/data/storage/secure_credential_store.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';

class InMemorySecureCredentialStore implements SecureCredentialStore {
  final Map<String, CardCredentials> _credentials = {};

  @override
  Future<void> write(String cardId, CardCredentials credentials) async {
    _credentials[cardId] = credentials;
  }

  @override
  Future<CardCredentials> read(String cardId, {required String expiry}) async {
    final credentials = _credentials[cardId];
    if (credentials == null) {
      throw StateError('No credentials found for card $cardId');
    }
    return CardCredentials(
      cardNumber: credentials.cardNumber,
      expiry: expiry,
      cvv: credentials.cvv,
      pin: credentials.pin,
    );
  }

  @override
  Future<void> delete(String cardId) async {
    _credentials.remove(cardId);
  }
}
