import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/data/balance/gift_card_mall_client.dart';

import 'test_assets.dart';

void main() {
  test('detects DataDome bot protection responses', () {
    expect(
      GiftCardMallClient.looksLikeBotProtection(
        statusCode: 405,
        headers: Headers.fromMap(
          <String, List<String>>{
            'x-datadome': <String>['protected']
          },
        ),
        body: sampleBotProtectionHtml,
      ),
      isTrue,
    );
  });

  test('does not flag a normal balance page as bot protection', () {
    expect(
      GiftCardMallClient.looksLikeBotProtection(
        statusCode: 200,
        headers: Headers(),
        body: sampleBalanceHtml,
      ),
      isFalse,
    );
  });
}
