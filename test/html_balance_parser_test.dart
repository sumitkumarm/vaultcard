import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/data/balance/html_balance_parser.dart';
import 'package:vaultcard/src/domain/models/parser_config.dart';

import 'test_assets.dart';

void main() {
  test('parses balance and transactions from fixture html', () {
    const parser = HtmlBalanceParser();
    const config = ParserConfig(
      version: 1,
      endpointUrl: 'https://example.com',
      formFields: ParserFormFields(
        cardNumber: 'cardNumber',
        expiryMonth: 'expMonth',
        expiryYear: 'expYear',
        cvv: 'cvv',
        pin: 'pin',
      ),
      balanceSelector: '.balance-amount',
      transactionSelector: 'table.transactions tbody tr',
      transactionFields: ParserTransactionFields(
        date: '.date',
        description: '.description',
        amount: '.amount',
      ),
    );

    final result = parser.parse(sampleBalanceHtml, config);

    expect(result.balance, 42.15);
    expect(result.transactions, hasLength(2));
    expect(result.transactions.first.description, 'Coffee Shop');
    expect(result.transactions.first.amount, -5.25);
  });
}
