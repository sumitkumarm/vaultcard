import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/services/gift_card_mall_browser_bridge.dart';

void main() {
  const bridge = GiftCardMallBrowserBridge();

  test('parses balance summary capture from browser bridge message', () {
    final message = jsonEncode(<String, Object?>{
      'url': '/api/card/getCardBalanceSummary',
      'requestBody': jsonEncode(<String, Object?>{
        'cardNumber': '4111111111111111',
        'expirationMonth': 9,
        'expirationYear': 2034,
        'securityCode': '123',
        'rmsSessionId': 'session-123',
      }),
      'responseBody': jsonEncode(<String, Object?>{
        'success': true,
        'result': <String, Object?>{
          'balances': <String, Object?>{
            'openingBalance': 200,
            'closingBalance': 42.15,
            'pendingBalance': 0,
            'currencyCode': 'USD',
          },
        },
        'access_token': 'token-abc',
      }),
    });

    final summary = bridge.parseSummaryCapture(message);

    expect(summary, isNotNull);
    expect(summary!.balance, 42.15);
    expect(summary.accessToken, 'token-abc');
    expect(summary.rmsSessionId, 'session-123');
  });

  test('parses transactions capture into balance result', () {
    const summary = GiftCardMallSummaryCapture(
      balance: 0,
      currencyCode: 'USD',
      accessToken: 'token-abc',
      rmsSessionId: 'session-123',
    );
    final message = jsonEncode(<String, Object?>{
      'url': '/api/card/getCardTransactions',
      'responseBody': jsonEncode(<String, Object?>{
        'success': true,
        'result': <String, Object?>{
          'transactions': <Map<String, Object?>>[
            <String, Object?>{
              'transactionDate': '2026-04-05T02:11:20.339Z',
              'merchantDescription': 'WWW.MAIDINTHEBAYAREA HAYWARD USA',
              'amount': -200,
            },
            <String, Object?>{
              'transactionDate': '2026-04-03T01:20:57.622Z',
              'description': 'Value Load -- Activation',
              'amount': 200,
            },
          ],
        },
      }),
    });

    final result = bridge.parseTransactionsResult(message, summary: summary);

    expect(result, isNotNull);
    expect(result!.balance, 0);
    expect(result.transactions, hasLength(2));
    expect(result.transactions.first.amount, -200);
    expect(
      result.transactions.first.description,
      'WWW.MAIDINTHEBAYAREA HAYWARD USA',
    );
  });
}
