import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/utils/validators.dart';

void main() {
  test('validates card number length', () {
    expect(validateCardNumber('4111111111111111'), isNull);
    expect(validateCardNumber('123'), isNotNull);
  });

  test('validates expiry format', () {
    expect(validateExpiry('05/27'), isNull);
    expect(validateExpiry('5/2027'), isNotNull);
  });

  test('formats expiry digits while typing', () {
    expect(formatExpiryInput('0'), '0');
    expect(formatExpiryInput('0527'), '05/27');
    expect(formatExpiryInput('05/27'), '05/27');
    expect(formatExpiryInput('05-2027'), '05/20');
  });
}
