import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/slash/completion.dart';

import '../control_test_harness.dart';

void main() {
  late ControlHarness h;
  late CompletionEngine engine;
  setUp(() async {
    h = await ControlHarness.create();
    addTearDown(h.dispose);
    engine = CompletionEngine(h.bus.visibleSpecs);
  });

  List<String> labels(String text) =>
      engine.complete(text).candidates.map((c) => c.label).toList();

  /// 按控制器应用候选的同一规则算出应用后的完整文本
  /// （text.substring(0, replaceStart) + insert）。
  String applied(String text, String label) {
    final r = engine.complete(text);
    final c = r.candidates.firstWhere((c) => c.label == label);
    return text.substring(0, r.replaceStart) + c.insert;
  }

  group('段一 命名空间', () {
    test('空输入与单独 /：全部 ns，insert 带点号', () {
      for (final text in ['', '/']) {
        final r = engine.complete(text);
        expect(r.segment, CompletionSegment.namespace, reason: text);
        expect(labels(text), containsAll(['sys', 'diary', 'chat', 'auth']));
        expect(
          r.candidates.firstWhere((c) => c.label == 'diary').insert,
          'diary.',
        );
      }
    });

    test('ns 前缀过滤；replaceStart 含前导 / 偏移', () {
      expect(labels('d'), ['diary']);
      expect(labels('/d'), ['diary']);
      expect(engine.complete('d').replaceStart, 0);
      expect(engine.complete('/d').replaceStart, 1);
      expect(labels('/xyz'), isEmpty);
    });
  });

  group('段二 动词', () {
    test('点号形态：diary. 列全部，diary.l 前缀过滤', () {
      final all = engine.complete('diary.');
      expect(all.segment, CompletionSegment.verb);
      expect(all.replaceStart, 0);
      expect(labels('diary.'), contains('list'));
      // ns 必须精确：di. 前缀不能把 diary 的动词拉出来。
      expect(labels('di.l'), isEmpty);
      expect(labels('diary.l'), ['list']);
    });

    test('空格形态：/diary 与 /diary l', () {
      final r = engine.complete('/diary ');
      expect(r.segment, CompletionSegment.verb);
      // body='diary '，最后空白 end=6，加前导 / 偏移 1。
      expect(r.replaceStart, 7);
      expect(labels('/diary l'), ['list']);
    });

    test('动词含点：sys.clock.', () {
      expect(labels('sys.clock.'), contains('clock.set'));
    });

    test('点号形态应用候选：insert 保留 ns，完整文本正确（G4-BUG-2）', () {
      // 不带前导 / 同样从 body 起点替换。
      expect(applied('diary.l', 'list'), 'diary.list ');
      expect(applied('/diary.l', 'list'), '/diary.list ');
      // 动词自身含点：ns 与动词里的点都要保留。
      expect(applied('/sys.clock.', 'clock.set'), '/sys.clock.set ');
      // 前缀为空（/diary.）也要拼回 ns。
      expect(applied('/diary.', 'prune'), '/diary.prune ');
      expect(applied('/sys.pi', 'ping'), '/sys.ping ');
    });

    test('空格形态应用候选回归：只替换动词 token，ns 不动', () {
      expect(applied('/sys pi', 'ping'), '/sys ping ');
      expect(applied('/diary l', 'list'), '/diary list ');
    });

    test('精确命令：仍返回唯一候选，但应用结果仅多尾随空格（Enter 应放行）', () {
      for (final text in ['/sys.ping', 'sys.ping', '/sys ping']) {
        final r = engine.complete(text);
        expect(r.segment, CompletionSegment.verb, reason: text);
        expect(r.candidates.single.label, 'ping', reason: text);
        // 应用候选只补出尾随空格：控制器据此判定 Enter 不消费。
        expect(applied(text, 'ping').trimRight(), text, reason: text);
      }

      // 前缀场景应用后文本确有变化：Enter 仍应消费为补全。
      expect(applied('/sys.pi', 'ping').trimRight(), isNot('/sys.pi'));
    });

    test('hint 带级别与种类', () {
      final send = engine
          .complete('chat.')
          .candidates
          .firstWhere((c) => c.label == 'send');
      expect(send.hint, '级3 · write'); // G0：send 已升 3 级
    });
  });

  group('段三 参数', () {
    test('命令完整后：参数声明序，hint 带类型与必填星号', () {
      final r = engine.complete('chat.send ');
      expect(r.segment, CompletionSegment.param);
      final ls = r.candidates;
      final ids = ls.map((c) => c.label).toList();
      expect(ids.indexOf('--id'), lessThan(ids.indexOf('--text')));
      final id = ls.firstWhere((c) => c.label == '--id');
      expect(id.hint, 'string*');
      expect(id.insert, '--id ');
    });

    test('前缀过滤与已出现剔除', () {
      expect(labels('diary.list --li'), ['--limit']);
      final after = labels('diary.list --limit 5 ');
      expect(after, isNot(contains('--limit')));
      expect(after, contains('--month'));
    });

    test('布尔参数 hint 为 boolean（非必填不带星）', () {
      final keep = engine
          .complete('diary.reset ')
          .candidates
          .firstWhere((c) => c.label == '--keep-seeds');
      expect(keep.hint, 'boolean');
    });

    test('--confirm 只对破坏性 3 级出现（chat.send 不出现）', () {
      expect(labels('diary.prune '), contains('--confirm'));
      expect(labels('chat.send '), isNot(contains('--confirm')));
      // 已显式给过则消失。
      expect(labels('diary.prune --confirm '), isNot(contains('--confirm')));
    });

    test('全局 --stay/--format/--timeout 常驻', () {
      final ls = labels('sys.ping ');
      expect(ls, containsAll(['--stay', '--format', '--timeout']));
    });

    test('未知命令上输参数：none', () {
      expect(engine.complete('ghost.verb --x').segment, CompletionSegment.none);
    });
  });

  group('构建风味裁剪（不加二次黑白名单）', () {
    test('release 下 debug-only 命令物理不在补全源', () async {
      final rel = await ControlHarness.create(
        buildMode: ControlBuildMode.release,
      );
      addTearDown(rel.dispose);
      final relEngine = CompletionEngine(rel.bus.visibleSpecs);

      expect(relEngine.complete('sys.clock.').candidates, isEmpty);
      // 正常命令仍在。
      expect(relEngine.complete('diary.').candidates, isNotEmpty);
      // debug 引擎对照：clock.set 可见。
      expect(labels('sys.clock.'), contains('clock.set'));
    });
  });
}
