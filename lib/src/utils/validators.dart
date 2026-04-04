String? validateCardNumber(String value) {
  final sanitized = value.replaceAll(RegExp(r'[\s-]'), '');
  if (sanitized.length != 16 || int.tryParse(sanitized) == null) {
    return 'Enter a valid 16-digit card number.';
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
