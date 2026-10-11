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

    final headingMatches =
        RegExp(r'^###\s+`([a-z][\w.-]*)`', multiLine: true).allMatches(text);

    // 小节文本表（标题 → 正文），debug 标注与「起始」分期都在正文里。
    final sections = <String, String>{};
    final names = <String>[];
    for (var i = 0; i < headingMatches.length; i++) {
      final m = headingMatches.elementAt(i);
      final start = m.start;
      final end = i + 1 < headingMatches.length
          ? headingMatches.elementAt(i + 1).start
          : text.length;
      sections[m.group(1)!] = text.substring(start, end);
      names.add(m.group(1)!);
    }
    final headings = names.toSet();

    for (final spec in specs) {
      expect(
        headings,
        contains(spec.name),
        reason: '${spec.name} 已注册但手册缺小节',
      );

      if (spec.debugOnly) {
        // 标题行或其注解行必须出现 debug 标注（手册用「仅 debug」）。
        final block = text.substring(
          text.indexOf('### `${spec.name}`'),
        );
        final untilNext = block.indexOf('\n### ', 4);
        final section =
            untilNext == -1 ? block : block.substring(0, untilNext);
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
        expect(spec.destructive, isTrue,
            reason: '${spec.name}：需确认的 3 级命令必须显式标 destructive'
                '（set-pin 的二次输入 PIN 除外）');
      }
    }

    // 反向：手册标注「起始 P1」的小节必须都在 manifest；
    // P2/P3/P4 命令（chat/console/badge/diary.seed）不在本批。
    for (final entry in sections.entries) {
      if (!entry.value.contains('起始 P1')) continue;
      expect(
        specs.map((s) => s.name),
        contains(entry.key),
        reason: '手册把 ${entry.key} 标为 P1，但 manifest 未注册',
      );
    }
  });
}
