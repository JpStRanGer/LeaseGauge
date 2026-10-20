import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class StartupReminderController {
  Future<bool> isSupported();
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

class StartupReminderService implements StartupReminderController {
  static const _channel = MethodChannel(
    'com.strangestudio.leasegauge/startup_reminder',
  );

  bool get _canUseAndroidChannel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isSupported() async {
    if (!_canUseAndroidChannel) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> isEnabled() async {
    if (!_canUseAndroidChannel) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!_canUseAndroidChannel) return;
    await _channel.invokeMethod<void>('setEnabled', enabled);
  }
}
