import 'dart:io';

import 'package:flutter/services.dart';

/// Android foreground notification so the mother HTTP API stays reachable in background.
class MotherApiForegroundService {
  MotherApiForegroundService._();
  static final MotherApiForegroundService instance = MotherApiForegroundService._();

  static const _channel = MethodChannel('com.veneranda.shop/platform');

  Future<void> startIfSupported() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startMotherApiForeground');
    } catch (_) {
      // Best effort; API server still runs in-process.
    }
  }

  Future<void> stopIfSupported() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopMotherApiForeground');
    } catch (_) {}
  }
}
