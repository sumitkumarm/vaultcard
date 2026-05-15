import 'package:intl/intl.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';

CardNetwork inferNetwork(String cardNumber) {
  final sanitized = cardNumber.replaceAll(RegExp(r'[\s-]'), '');
  if (sanitized.startsWith('4')) {
    return CardNetwork.visa;
  }
  if (sanitized.length >= 2) {
    final firstTwo = int.tryParse(sanitized.substring(0, 2));
    if (firstTwo != null && firstTwo >= 51 && firstTwo <= 55) {
      return CardNetwork.mastercard;
    }
  }
  if (sanitized.length >= 4) {
    final firstFour = int.tryParse(sanitized.substring(0, 4));
    if (firstFour != null && firstFour >= 2221 && firstFour <= 2720) {
      return CardNetwork.mastercard;
    }
  }
  return CardNetwork.unknown;
}

bool isValidCardNumber(String cardNumber) {
  final sanitized = cardNumber.replaceAll(RegExp(r'[\s-]'), '');
  if (sanitized.length != 16 || int.tryParse(sanitized) == null) {
    return false;
  }
  if (inferNetwork(sanitized) == CardNetwork.unknown) {
    return false;
  }
  var sum = 0;
  var doubleDigit = false;
  for (var i = sanitized.length - 1; i >= 0; i--) {
    var digit = int.parse(sanitized[i]);
    if (doubleDigit) {
      digit *= 2;
      if (digit > 9) {
        digit -= 9;
      }
    }
    sum += digit;
    doubleDigit = !doubleDigit;
  }
  return sum % 10 == 0;
}

String maskCardNumber(String cardNumber) {
  final trimmed = cardNumber.replaceAll(RegExp(r'\s+'), '');
  final last4 = trimmed.substring(trimmed.length - 4);
  return '**** **** **** $last4';
}

String formatCurrency(double value) {
  return NumberFormat.currency(symbol: '\$').format(value);
}

String formatDateTime(DateTime? value) {
  if (value == null) {
    return 'Never';
  }
  return DateFormat.yMMMd().add_jm().format(value);
}

String formatExpiry(String expiry) {
  final parts = expiry.split('/');
  if (parts.length != 2) {
    return expiry;
  }
  return '${parts.first}/${parts.last}';
}

List<VaultCard> sortCards(List<VaultCard> cards, CardSortOption option) {
  final sorted = [...cards];
  switch (option) {
    case CardSortOption.dateAddedNewest:
      sorted.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case CardSortOption.balanceLowToHigh:
      sorted.sort((a, b) => (a.balance ?? 0).compareTo(b.balance ?? 0));
    case CardSortOption.balanceHighToLow:
      sorted.sort((a, b) => (b.balance ?? 0).compareTo(a.balance ?? 0));
    case CardSortOption.expirySoonest:
      sorted.sort((a, b) => a.expiry.compareTo(b.expiry));
  }
  return sorted;
}
