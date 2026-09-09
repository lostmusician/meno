import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meno/services/window_appearance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('meno/window_appearance_test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends glass changes through the macOS appearance bridge', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final service = WindowAppearanceService(channel: channel, isMacOS: true);

    expect(service.isSupported, isTrue);
    await service.setGlassMode(true);
    await service.setGlassMode(false);

    expect(calls, [
      isA<MethodCall>()
          .having((call) => call.method, 'method', 'setGlassMode')
          .having((call) => call.arguments, 'arguments', true),
      isA<MethodCall>()
          .having((call) => call.method, 'method', 'setGlassMode')
          .having((call) => call.arguments, 'arguments', false),
    ]);
  });

  test('does not invoke the native bridge on other platforms', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called = true;
          return null;
        });
    final service = WindowAppearanceService(channel: channel, isMacOS: false);

    expect(service.isSupported, isFalse);
    await service.setGlassMode(true);

    expect(called, isFalse);
  });
}
