import 'package:dio/dio.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/parser_config.dart';

class GiftCardMallResponse {
  const GiftCardMallResponse({
    required this.body,
    required this.statusCode,
  });

  final String body;
  final int statusCode;
}

class GiftCardMallClient {
  const GiftCardMallClient({Dio? dio}) : _dio = dio;

  final Dio? _dio;

  Future<GiftCardMallResponse> fetchBalance({
    required ParserConfig config,
    required CardCredentials credentials,
  }) async {
    final dio = _dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            responseType: ResponseType.plain,
            headers: const {
              'User-Agent': 'VaultCard/0.1',
            },
          ),
        );

    final response = await dio.post<String>(
      config.endpointUrl,
      data: {
        config.formFields.cardNumber: credentials.cardNumber,
        config.formFields.expiryMonth: credentials.expiryMonth,
        config.formFields.expiryYear: credentials.expiryYear,
        config.formFields.cvv: credentials.cvv,
        config.formFields.pin: credentials.pin,
      },
    );

    return GiftCardMallResponse(
      body: response.data ?? '',
      statusCode: response.statusCode ?? 0,
    );
  }
}
