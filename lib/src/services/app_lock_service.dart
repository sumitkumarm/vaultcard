import 'package:flutter/services.dart';

class AppLockService {
  AppLockService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('vaultcard/platform_security');

  final MethodChannel _channel;

  Future<void> enableSecureDisplay() async {
    await _channel.invokeMethod<void>('enableSecureDisplay');
  }

  Future<void> disableSecureDisplay() async {
    await _channel.invokeMethod<void>('disableSecureDisplay');
  }
}
