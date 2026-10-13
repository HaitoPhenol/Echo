import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/control_envelope.dart';
import 'package:echo/src/control/protocol/control_error.dart';
import 'package:echo/src/control/slash/result_view.dart';

ControlEnvelope ok(Map<String, Object?> result, {String cmd = 'x.y'}) =>
    ControlEnvelope(ok: true, cmd: cmd, ms: 3, result: result);

ControlEnvelope fail(
  ControlErrorCode code,
  String message, {
  int? need,
  String? elevate,
  int? retryAfterMs,
}) => ControlEnvelope.failure(
  'x.y',
  1,
  ControlException(
    code,
    message,
    need: need,
    elevate: elevate,
    retryAfterMs: retryAfterMs,
  ),
);

void main() {
  group('ErrorView', () {
    test('错误码/文案/need/elevate 扁平透出（G2 PIN 面板直连）', () {
      final v = viewOf(
        fail(
          ControlErrorCode.authRequired,
          '需要 3 级',
          need: 3,
          elevate: 'auth.unlock',
        ),
      );
      expect(v, isA<ErrorView>());
      final e = v as ErrorView;
      expect(e.code, 'AUTH_REQUIRED');
      expect(e.need, 3);
      expect(e.elevate, 'auth.unlock');
    });

    test('冷却字段透出', () {
      final v = viewOf(
        fail(ControlErrorCode.authCooldown, '冷却', retryAfterMs: 30000),
      ) as ErrorView;
      expect(v.retryAfterMs, 30000);
    });
  });

  group('TableView', () {
    test('items 对象数组成表；列＝键并集保序；缺键 null', () {
      final v = viewOf(
        ok({
          'items': [
            {'id': 'a', 'unread': true},
            {'id': 'b', 'title': '乙'},
          ],
        }),
      );
      expect(v, isA<TableView>());
      final t = v as TableView;
      expect(t.columns, ['id', 'unread', 'title']);
      expect(t.rows, [
        ['a', true, null],
        ['b', null, '乙'],
      ]);
    });

    test('空 items → 空表', () {
      final t = viewOf(ok({'items': <Object?>[]})) as TableView;
      expect(t.columns, isEmpty);
      expect(t.rows, isEmpty);
    });

    test('items 含非 Map 元素 → 不走表格，键值视图内嵌 JSON', () {
      final v = viewOf(
        ok({
          'items': ['a', 'b'],
        }),
      );
      expect(v, isA<KeyValueView>());
      final kv = v as KeyValueView;
      expect(kv.entries.single.value, isA<JsonView>());
    });
  });

  group('KeyValueView', () {
    test('标量 Map → 键值保序', () {
      final v = viewOf(
        ok({'model': 'MIX 2S', 'tempC': 33.0, 'powerW': 0.1, 'on': true}),
      ) as KeyValueView;
      expect(v.entries.map((e) => e.key), ['model', 'tempC', 'powerW', 'on']);
      expect(v.entries.first.value, 'MIX 2S');
    });

    test('嵌套 Map 递归成子 KeyValueView；List 降级内嵌 JSON', () {
      final v = viewOf(
        ok({
          'nav': {'index': 0, 'page': 'console'},
          'tags': ['a', 'b'],
        }),
      ) as KeyValueView;
      final nav = v.entries.firstWhere((e) => e.key == 'nav');
      expect(nav.value, isA<KeyValueView>());
      final sub = nav.value as KeyValueView;
      expect(sub.entries.map((e) => e.key), ['index', 'page']);
      final tags = v.entries.firstWhere((e) => e.key == 'tags');
      expect(tags.value, isA<JsonView>());
      expect((tags.value as JsonView).json, contains('"a"'));
    });

    test('空对象 → 空键值', () {
      final v = viewOf(ok({})) as KeyValueView;
      expect(v.entries, isEmpty);
    });
  });

  group('JsonView', () {
    test('缩进文本可作为长按复制源', () {
      final v = viewOf(
        ok({
          'items': [1, 2, 3],
        }),
      ) as KeyValueView;
      final j = v.entries.single.value as JsonView;
      expect(j.json, contains('\n  1'));
    });
  });
}
