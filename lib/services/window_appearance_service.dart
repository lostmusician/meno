import 'dart:io';

import 'package:flutter/services.dart';

class WindowAppearanceService {
  WindowAppearanceService({MethodChannel? channel, bool? isMacOS})
    : _channel = channel ?? const MethodChannel('meno/window_appearance'),
      _isMacOS = isMacOS ?? Platform.isMacOS;

  final MethodChannel _channel;
  final bool _isMacOS;

  Future<void> setGlassMode(bool enabled) async {
    if (!_isMacOS) return;
    try {
      await _channel.invokeMethod<void>('setGlassMode', enabled);
    } on MissingPluginException {
      // Widget tests and non-runner embeddings do not install the native bridge.
    }
  }
}
