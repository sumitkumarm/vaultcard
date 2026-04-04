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
}
