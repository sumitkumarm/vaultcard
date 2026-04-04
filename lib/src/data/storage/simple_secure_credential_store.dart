import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vaultcard/src/data/storage/secure_credential_store.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';

class SimpleSecureCredentialStore implements SecureCredentialStore {
  const SimpleSecureCredentialStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  final FlutterSecureStorage _storage;

  static String _key(String cardId) => 'card:$cardId:credentials';

  @override
  Future<void> write(String cardId, CardCredentials credentials) async {
    final payload = jsonEncode(
      {
        'cardNumber': credentials.cardNumber,
        'cvv': credentials.cvv,
        'pin': credentials.pin,
      },
    );
    await _storage.write(key: _key(cardId), value: payload);
  }

  @override
  Future<CardCredentials> read(String cardId, {required String expiry}) async {
    final value = await _storage.read(key: _key(cardId));
    if (value == null) {
      throw StateError('No credentials found for card $cardId');
    }
    final payload = jsonDecode(value) as Map<String, dynamic>;
    return CardCredentials(
      cardNumber: payload['cardNumber'] as String,
      expiry: expiry,
      cvv: payload['cvv'] as String,
      pin: payload['pin'] as String,
    );
  }

  @override
  Future<void> delete(String cardId) async {
    await _storage.delete(key: _key(cardId));
  }
}
