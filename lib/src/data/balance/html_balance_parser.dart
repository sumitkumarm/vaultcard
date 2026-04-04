import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/parser_config.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

class HtmlBalanceParser {
  const HtmlBalanceParser();

  BalanceResult parse(String html, ParserConfig config) {
    final document = html_parser.parse(html);
    final balanceNode = document.querySelector(config.balanceSelector);
    if (balanceNode == null) {
      throw const FormatException('Balance element not found');
    }

    final balance = _parseAmount(balanceNode.text);
    final txRows = document.querySelectorAll(config.transactionSelector);
    final transactions = txRows.map((row) {
      final dateText =
          row.querySelector(config.transactionFields.date)?.text.trim() ?? '';
      final description = row
              .querySelector(config.transactionFields.description)
              ?.text
              .trim() ??
          'Unknown';
      final amountText =
          row.querySelector(config.transactionFields.amount)?.text.trim() ?? '0';

      return CardTransaction(
        date: DateFormat('MM/dd/yyyy').parse(dateText),
        description: description,
        amount: _parseAmount(amountText),
      );
    }).toList();

    return BalanceResult(
      balance: balance,
      transactions: transactions,
      fetchedAt: DateTime.now(),
    );
  }

  double _parseAmount(String value) {
    final normalized = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.parse(normalized);
  }
}
