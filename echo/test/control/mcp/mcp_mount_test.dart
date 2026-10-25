import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/bootstrap.dart';

import '../control_test_harness.dart';

/// R4｜MCP 挂载开关：默认关闭、仅 debug + 显式请求才创建传输。
///
/// release 分支的“物理不挂载”由 `kDebugMode` 常量保证；这里用显式的
/// `debugMode` 参数模拟 release（false），断言 server/transport 不创建。
void main() {
  late ControlHarness h;

  setUp(() async {
    h = await ControlHarness.create();
  });

  tearDown(() => h.dispose());

  test('默认（未带 --mcp）不创建 server/transport', () {
    expect(
      ControlBootstrap.createMcpTransport(bus: h.bus, requested: false),
      isNull,
    );
  });

  test('release 构建即使请求也不创建', () {
    expect(
      ControlBootstrap.createMcpTransport(
        bus: h.bus,
        requested: true,
        debugMode: false,
      ),
      isNull,
    );
  });

  test('debug + 显式请求才创建，且不自动 attach', () async {
    final transport = ControlBootstrap.createMcpTransport(
      bus: h.bus,
      requested: true,
      debugMode: true,
    );
    expect(transport, isNotNull);
    expect(transport!.attached, isFalse, reason: '创建不等于挂载');
    expect(transport.server.bus, h.bus);
    await transport.detach();
  });
}
