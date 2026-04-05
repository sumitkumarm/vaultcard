import 'package:vaultcard/src/domain/models/scan_result.dart';
import 'package:vaultcard/src/utils/card_utils.dart';

class ScanService {
  const ScanService();

  ScanResult extractFromText(String source) {
    final cardMatch =
        RegExp(r'(?:\d[\s-]?){16}').firstMatch(source)?.group(0)?.replaceAll(
              RegExp(r'[\s-]'),
              '',
            );
    final labeledExpiryMatch = RegExp(
      r'(?:exp|expiry)[:\s]*((0[1-9]|1[0-2])\/([0-9]{2}))',
      caseSensitive: false,
    ).firstMatch(source);
    final expiryMatch =
        labeledExpiryMatch ??
        RegExp(r'\b(0[1-9]|1[0-2])\/([0-9]{2})\b').firstMatch(source);
    final labeledCvvMatch = RegExp(
      r'cvv[:\s]*([0-9]{3,4})',
      caseSensitive: false,
    ).firstMatch(source);
    final cvvMatch = RegExp(r'\b\d{3,4}\b')
        .allMatches(source)
        .map((match) => match.group(0))
        .toList();

    final expiry = expiryMatch == null
        ? null
        : labeledExpiryMatch != null
            ? labeledExpiryMatch.group(1)
            : '${expiryMatch.group(1)}/${expiryMatch.group(2)}';
    final cvv = labeledCvvMatch?.group(1) ??
        (cvvMatch.length >= 2 ? cvvMatch.last : null);
    final network = cardMatch == null ? inferNetwork('') : inferNetwork(cardMatch);

    return ScanResult(
      cardNumber: cardMatch,
      expiry: expiry,
      cvv: cvv,
      network: network,
      confidence: cardMatch != null && expiry != null ? 0.8 : 0.45,
    );
  }
}
