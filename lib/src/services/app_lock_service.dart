import 'package:flutter/services.dart';

class AppLockService {
  AppLockService({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('vaultcard/platform_security');

  final MethodChannel _channel;

  Future<void> enableSecureDisplay() async {
    try {
      await _channel.invokeMethod<void>('enableSecureDisplay');
    } on MissingPluginException {
      // Web and desktop QA builds do not have the native secure-display plugin.
    }
  }

  Future<void> disableSecureDisplay() async {
    try {
      await _channel.invokeMethod<void>('disableSecureDisplay');
    } on MissingPluginException {
      // Web and desktop QA builds do not have the native secure-display plugin.
    }
  }
}
