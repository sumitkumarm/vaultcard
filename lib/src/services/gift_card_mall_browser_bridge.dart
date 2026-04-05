import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

class GiftCardMallSummaryCapture {
  const GiftCardMallSummaryCapture({
    required this.balance,
    required this.currencyCode,
    required this.accessToken,
    required this.rmsSessionId,
  });

  final double balance;
  final String currencyCode;
  final String accessToken;
  final String rmsSessionId;
}

class GiftCardMallBrowserBridge {
  const GiftCardMallBrowserBridge();

  static const String channelName = 'VaultCardBridge';
  static const String siteUrl = 'https://mygift.giftcardmall.com/';

  String installScript() {
    return '''
(() => {
  if (window.__vaultCardBridgeInstalled) {
    return;
  }
  window.__vaultCardBridgeInstalled = true;

  const post = (payload) => {
    try {
      $channelName.postMessage(JSON.stringify(payload));
    } catch (_) {}
  };

  const originalFetch = window.fetch;
  window.fetch = async (...args) => {
    const response = await originalFetch(...args);
    try {
      const request = args[1] || {};
      const clone = response.clone();
      const text = await clone.text();
      post({
        transport: 'fetch',
        url: typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) || '',
        method: request.method || 'GET',
        requestBody: request.body || null,
        responseBody: text,
        status: response.status
      });
    } catch (_) {}
    return response;
  };

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.__vaultCardMethod = method;
    this.__vaultCardUrl = url;
    return originalOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function(body) {
    this.__vaultCardRequestBody = body || null;
    this.addEventListener('load', function() {
      try {
        post({
          transport: 'xhr',
          url: this.__vaultCardUrl || '',
          method: this.__vaultCardMethod || 'GET',
          requestBody: this.__vaultCardRequestBody || null,
          responseBody: this.responseText || '',
          status: this.status
        });
      } catch (_) {}
    });
    return originalSend.apply(this, arguments);
  };
})();
''';
  }

  String buildAutofillScript(CardCredentials credentials) {
    final cardNumber = jsonEncode(credentials.cardNumber);
    final expiryMonth = jsonEncode(int.parse(credentials.expiryMonth));
    final expiryYear = jsonEncode(int.parse(credentials.expiryYear));
    final securityCode = jsonEncode(credentials.cvv);

    return '''
(() => {
  const setValue = (selectors, value) => {
    for (const selector of selectors) {
      const field = document.querySelector(selector);
      if (!field) {
        continue;
      }
      field.focus();
      field.value = value;
      field.dispatchEvent(new Event('input', { bubbles: true }));
      field.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }
    return false;
  };

  const results = {
    cardNumber: setValue([
      'input[name="cardNumber"]',
      'input[id*="cardNumber"]',
      'input[autocomplete="cc-number"]',
      'input[inputmode="numeric"]'
    ], $cardNumber),
    expirationMonth: setValue([
      'input[name="expirationMonth"]',
      'input[id*="expirationMonth"]',
      'select[name="expirationMonth"]',
      'select[id*="expirationMonth"]',
      'input[name="expMonth"]'
    ], String($expiryMonth)),
    expirationYear: setValue([
      'input[name="expirationYear"]',
      'input[id*="expirationYear"]',
      'select[name="expirationYear"]',
      'select[id*="expirationYear"]',
      'input[name="expYear"]'
    ], String($expiryYear)),
    securityCode: setValue([
      'input[name="securityCode"]',
      'input[id*="securityCode"]',
      'input[name="cvv"]',
      'input[id*="cvv"]',
      'input[autocomplete="cc-csc"]'
    ], $securityCode),
  };

  $channelName.postMessage(JSON.stringify({
    type: 'autofillResult',
    result: results
  }));
})();
''';
  }

  String buildTransactionsFetchScript({
    required String token,
    required String rmsSessionId,
  }) {
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(days: 60));
    final payload = jsonEncode(<String, Object>{
      'pageIndex': 0,
      'itemPerPage': 25,
      'endDate': now.toIso8601String(),
      'startDate': start.toIso8601String(),
      'preferredLanguage': 'en-US',
      'rmsSessionId': rmsSessionId,
    });
    final encodedToken = jsonEncode(token);

    return '''
window.fetch('/api/card/getCardTransactions', {
  method: 'POST',
  credentials: 'include',
  headers: {
    'accept': 'application/json, text/plain, */*',
    'content-type': 'application/json',
    'token': $encodedToken
  },
  body: ${jsonEncode(payload)}
});
''';
  }

  GiftCardMallSummaryCapture? parseSummaryCapture(String message) {
    final payload = _decodeMessage(message);
    if (payload == null) {
      return null;
    }
    final url = payload['url'] as String? ?? '';
    if (!url.contains('/api/card/getCardBalanceSummary')) {
      return null;
    }

    final responseBody = payload['responseBody'] as String? ?? '';
    final response = jsonDecode(responseBody) as Map<String, dynamic>;
    if (response['success'] != true) {
      return null;
    }
    final result = response['result'] as Map<String, dynamic>;
    final balances = result['balances'] as Map<String, dynamic>;
    final requestBody = jsonDecode(payload['requestBody'] as String? ?? '{}')
        as Map<String, dynamic>;
    return GiftCardMallSummaryCapture(
      balance: (balances['closingBalance'] as num?)?.toDouble() ?? 0,
      currencyCode: balances['currencyCode'] as String? ?? 'USD',
      accessToken: response['access_token'] as String? ?? '',
      rmsSessionId: requestBody['rmsSessionId'] as String? ?? '',
    );
  }

  BalanceResult? parseTransactionsResult(
    String message, {
    required GiftCardMallSummaryCapture summary,
  }) {
    final payload = _decodeMessage(message);
    if (payload == null) {
      return null;
    }
    final url = payload['url'] as String? ?? '';
    if (!url.contains('/api/card/getCardTransactions')) {
      return null;
    }
    final responseBody = payload['responseBody'] as String? ?? '';
    final response = jsonDecode(responseBody) as Map<String, dynamic>;
    if (response['success'] != true) {
      return null;
    }
    final result = response['result'] as Map<String, dynamic>;
    final transactions = (result['transactions'] as List<dynamic>? ?? const [])
        .map((item) => _parseTransaction(item as Map<String, dynamic>))
        .toList();
    return BalanceResult(
      balance: summary.balance,
      transactions: transactions,
      fetchedAt: DateTime.now(),
    );
  }

  Map<String, dynamic>? _decodeMessage(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return decoded;
  }

  CardTransaction _parseTransaction(Map<String, dynamic> json) {
    final description = json['merchantDescription'] as String? ??
        json['description'] as String? ??
        'GiftCardMall transaction';
    return CardTransaction(
      date: DateTime.parse(json['transactionDate'] as String).toLocal(),
      description: description.trim(),
      amount: (json['amount'] as num).toDouble(),
    );
  }

  String formatSummaryStatus(GiftCardMallSummaryCapture summary) {
    final currency =
        summary.currencyCode.isEmpty ? 'USD' : summary.currencyCode;
    final amount = NumberFormat.currency(name: currency, symbol: '\$')
        .format(summary.balance);
    return 'GiftCardMall session connected. Balance summary captured: $amount.';
  }
}
