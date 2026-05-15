import 'package:vaultcard/src/utils/card_utils.dart';

String? validateCardNumber(String value) {
  if (!isValidCardNumber(value)) {
    return 'Enter a valid Visa or Mastercard number.';
  }
  return null;
}

String? validateExpiry(String value) {
  final match = RegExp(r'^(0[1-9]|1[0-2])\/([0-9]{2})$').hasMatch(value);
  if (!match) {
    return 'Use MM/YY.';
  }
  return null;
}

String formatExpiryInput(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  final trimmed = digits.length > 4 ? digits.substring(0, 4) : digits;
  if (trimmed.length <= 2) {
    return trimmed;
  }
  return '${trimmed.substring(0, 2)}/${trimmed.substring(2)}';
}

String? validateCvv(String value) {
  if (!RegExp(r'^\d{3,4}$').hasMatch(value)) {
    return 'Enter a valid CVV.';
  }
  return null;
}

String? validatePin(String value) {
  if (!RegExp(r'^\d{4,8}$').hasMatch(value)) {
    return 'Enter the card PIN.';
  }
  return null;
}
