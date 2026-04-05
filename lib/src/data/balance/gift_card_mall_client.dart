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

class GiftCardMallBotProtectionException implements Exception {
  const GiftCardMallBotProtectionException([
    this.message =
        'GiftCardMall rejected the request behind a JavaScript challenge.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class GiftCardMallHttpException implements Exception {
  const GiftCardMallHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode: $message';
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
            validateStatus: (_) => true,
            headers: const <String, Object>{
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/135.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
    if (looksLikeBotProtection(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.data ?? '',
    )) {
      throw const GiftCardMallBotProtectionException();
    }
    if ((response.statusCode ?? 0) >= 400) {
      throw GiftCardMallHttpException(
        response.statusCode ?? 0,
        'Unexpected response from GiftCardMall.',
      );
    }

    return GiftCardMallResponse(
      body: response.data ?? '',
      statusCode: response.statusCode ?? 0,
    );
  }

  static bool looksLikeBotProtection({
    required int? statusCode,
    required Headers headers,
    required String body,
  }) {
    final normalizedBody = body.toLowerCase();
    final datadomeHeader = headers.value('x-datadome')?.toLowerCase();
    return datadomeHeader == 'protected' ||
        normalizedBody
            .contains('please enable js and disable any ad blocker') ||
        normalizedBody.contains('captcha-delivery.com') ||
        (statusCode == 405 && normalizedBody.contains('datadome'));
  }
}
