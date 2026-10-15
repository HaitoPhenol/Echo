import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';

import 'control_test_harness.dart';

/// 手册即契约（docs/ecp/ecp-commands.md 开头规则）：manifest 里
/// 每条命令都必须有手册小节；debug-only 标题必须显式标注；破坏性
/// 3 级必须 --confirm。冻结后漏加小节 = CI 红。
void main() {
  test('manifest ↔ 命令手册一致', () async {
    final h = await ControlHarness.create();
    addTearDown(h.dispose);

    // 用与生产完全相同的注册序列（debug 风味，含 debug-only）。
    final specs = h.bus.visibleSpecs;
    expect(specs, isNotEmpty);

    final manual = File('../docs/ecp/ecp-commands.md');
    expect(manual.existsSync(), isTrue, reason: '从 echo/ 包目录运行测试');
    final text = manual.readAsStringSync();

    final headingMatches = RegExp(
      r'^###\s+`([a-z][\w.-]*)`',
      multiLine: true,
    ).allMatches(text);

    // 小节标题集合（仅标题名，正文按需即时切取）。
    final headings = <String>{for (final m in headingMatches) m.group(1)!};

    for (final spec in specs) {
      expect(headings, contains(spec.name), reason: '${spec.name} 已注册但手册缺小节');

      if (spec.debugOnly) {
        // 标题行或其注解行必须出现 debug 标注（手册用「仅 debug」）。
        final block = text.substring(text.indexOf('### `${spec.name}`'));
        final untilNext = block.indexOf('\n### ', 4);
        final section = untilNext == -1 ? block : block.substring(0, untilNext);
        expect(
          section.contains('仅 debug') || section.contains('debug-only'),
          isTrue,
          reason: '${spec.name} 是 debug-only，手册标题行必须标注',
        );
      }

      if (spec.destructive) {
        expect(
          spec.requiresConfirm,
          isTrue,
          reason: '${spec.name} 标 destructive 就必须要求 --confirm',
        );
      }

      // 清单内部一致性：受控动词表/命名空间由构造器保证，这里再钉
      // 一条：3 级命令若要确认，错误语义必须走 confirmRequired。
      if (spec.level == ControlLevel.admin && spec.requiresConfirm) {
        expect(
          spec.destructive,
          isTrue,
          reason:
              '${spec.name}：需确认的 3 级命令必须显式标 destructive'
              '（set-pin 的二次输入 PIN 除外）',
        );
      }
    }

    // 反向：手册每个小节都必须对应 manifest 已注册命令——手册即契约，
    // 正向「注册缺小节」与反向「有节未注册」都判红；不再按分期
    // （P1/P4）写死豁免名单，一律按**实际注册**断言（debug 风味已含
    // DebugOnly 命令）。
    final registered = specs.map((s) => s.name).toSet();
    for (final name in headings) {
      expect(
        registered,
        contains(name),
        reason: '手册有 $name 小节，但 manifest 未注册（或名称拼写不一致）',
      );
    }
  });
}
