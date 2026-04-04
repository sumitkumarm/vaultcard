import 'package:vaultcard/src/domain/models/card_credentials.dart';

abstract interface class SecureCredentialStore {
  Future<void> write(String cardId, CardCredentials credentials);
  Future<CardCredentials> read(String cardId, {required String expiry});
  Future<void> delete(String cardId);
}
