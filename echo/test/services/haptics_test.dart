import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/services/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Haptics 的调用方全部 fire-and-forget，通道异常若不收口会成为
  // 未捕获异步错误（G13）：mock 通道直接抛错，tick/confirm 应正常完成。
  testWidgets('通道抛错时静默降级：tick/confirm 不抛未捕获异步异常', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('echo/haptics'),
      (call) async => throw PlatformException(code: 'unavailable'),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('echo/haptics'),
        null,
      );
    });

    await Haptics.tick();
    await Haptics.confirm();
  });
}
