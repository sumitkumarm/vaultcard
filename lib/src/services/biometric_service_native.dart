import 'package:local_auth/local_auth.dart';

class BiometricService {
  const BiometricService({LocalAuthentication? localAuthentication})
      : _localAuthentication = localAuthentication;

  final LocalAuthentication? _localAuthentication;

  Future<bool> authenticate(String reason) async {
    final auth = _localAuthentication ?? LocalAuthentication();
    final isSupported = await auth.isDeviceSupported();
    if (!isSupported) {
      return false;
    }
    return auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
  }
}
