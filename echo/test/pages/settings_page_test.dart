import 'dart:async';
import 'dart:io';

import 'package:echo/src/ai/ai_api_client.dart';
import 'package:echo/src/ai/ai_config.dart';
import 'package:echo/src/ai/ai_config_store.dart';
import 'package:echo/src/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements AiHttpTransport {
  Uri? lastUri;

  @override
  Future<AiHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    lastUri = uri;
    return const AiHttpResponse(statusCode: 200, body: '{}');
  }
}

/// 同步建临时目录 + 空配置存储。
///
/// widget 测试运行在 fake-async 区里，真实文件 I/O 的 Future 不会推进，
/// 因此这里不走 `load()`；持久化本身由 `ai_config_store_test.dart`
/// 用普通 `test()` 覆盖。
AiConfigStore _createStore() {
  final dir = Directory.systemTemp.createTempSync('echo_settings_page_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return AiConfigStore(directory: dir);
}

Widget _wrap(Widget child) => MaterialApp(home: child);

/// 逐帧推进路由/提示动画。
///
/// 编辑页有光标闪烁，`pumpAndSettle` 会因持续排帧而永不返回，
/// 因此这里统一用固定帧数推进。
Future<void> _pumpFrames(WidgetTester tester, [int ms = 500]) async {
  final frames = (ms / 16).ceil();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 编辑页表单长于视口，保存按钮位于底部，需滚动后点击。
Future<void> _scrollEditorToSave(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byType(AiProfileEditorPage),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(find.text('保存'), 200, scrollable: scrollable);
}

void main() {
  testWidgets('空配置展示引导文案，MCP 段如实标注未初始化', (tester) async {
    final store = _createStore();
    await tester.pumpWidget(
      _wrap(
        SettingsPage(
          store: store,
          apiClient: AiApiClient(transport: _FakeTransport()),
        ),
      ),
    );

    expect(find.text('尚未配置模型'), findsOneWidget);
    expect(find.text('MCP 未挂载'), findsOneWidget);
    expect(find.text('控制面未初始化，无法读取工具清单。'), findsOneWidget);

    await tester.tap(find.text('新增模型配置'));
    await _pumpFrames(tester);
    expect(find.byType(AiProfileEditorPage), findsOneWidget);
    // 表单全量构建：视口内先出现名称/URL/Key/模型名等字段。
    expect(find.byType(TextFormField), findsWidgets);

    // 空表单直接保存：停留在编辑页并给出校验提示。
    await _scrollEditorToSave(tester);
    await tester.tap(find.text('保存'));
    // 校验失败会自动滚回表单顶部，错误提示应可见。
    await _pumpFrames(tester, 300);
    expect(find.byType(AiProfileEditorPage), findsOneWidget);
    final scrollableState = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(AiProfileEditorPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollableState.position.pixels, 0);
    expect(find.text('请填写 Base URL'), findsOneWidget);
    expect(find.text('请填写模型名'), findsOneWidget);
  });

  testWidgets('新增配置后展示掩码 Key，连通测试显示成功', (tester) async {
    final store = _createStore();
    final transport = _FakeTransport();

    await tester.pumpWidget(
      _wrap(
        SettingsPage(
          store: store,
          apiClient: AiApiClient(transport: transport),
        ),
      ),
    );

    await tester.tap(find.text('新增模型配置'));
    await _pumpFrames(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '主力模型');
    await tester.enterText(fields.at(1), 'https://api.example.com/v1');
    await tester.enterText(fields.at(2), 'sk-1234567890abcd');
    await tester.enterText(fields.at(3), 'gpt-4o-mini');
    await _scrollEditorToSave(tester);
    await tester.tap(find.text('保存'));
    await _pumpFrames(tester);

    // 回到设置页：标题、掩码 Key、默认标记。
    expect(find.text('主力模型'), findsOneWidget);
    expect(find.text('••••••abcd'), findsOneWidget);
    expect(find.text('sk-1234567890abcd'), findsNothing);
    expect(find.text('默认'), findsOneWidget);
    expect(store.profiles, hasLength(1));
    expect(store.activeProfileId, store.profiles.single.id);

    await tester.tap(find.text('测试连接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('连接成功'), findsOneWidget);
    expect(
      transport.lastUri?.toString(),
      'https://api.example.com/v1/chat/completions',
    );
  });

  testWidgets('编辑配置不回填明文 Key，留空保存沿用原 Key', (tester) async {
    final store = _createStore();
    const existing = AiModelProfile(
      id: 'p1',
      name: '主力',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-12345678',
      model: 'm1',
    );
    unawaited(store.upsert(existing));

    await tester.pumpWidget(
      _wrap(
        SettingsPage(
          store: store,
          apiClient: AiApiClient(transport: _FakeTransport()),
        ),
      ),
    );

    await tester.tap(find.text('编辑'));
    await _pumpFrames(tester);

    // 编辑页不出现明文 Key，仅以掩码提示已保存。
    expect(find.text('sk-12345678'), findsNothing);
    expect(find.text('已保存 ••••••5678，留空则保持不变'), findsOneWidget);

    await _scrollEditorToSave(tester);
    await tester.tap(find.text('保存'));
    await _pumpFrames(tester);

    expect(store.profiles.single.apiKey, 'sk-12345678');
    expect(find.text('••••••5678'), findsOneWidget);
    expect(find.text('sk-12345678'), findsNothing);
  });

  testWidgets('第二条配置可设为默认，删除当前默认项后清空', (tester) async {
    final store = _createStore();
    const first = AiModelProfile(
      id: 'p1',
      name: '主力',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-12345678',
      model: 'm1',
    );
    const second = AiModelProfile(
      id: 'p2',
      name: '备用',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-87654321',
      model: 'm2',
    );
    unawaited(store.upsert(first));
    unawaited(store.upsert(second));

    await tester.pumpWidget(
      _wrap(
        SettingsPage(
          store: store,
          apiClient: AiApiClient(transport: _FakeTransport()),
        ),
      ),
    );

    // 默认项是第一条，「备用」卡片出现「设为默认」。
    expect(find.text('默认'), findsOneWidget);
    await tester.tap(find.text('设为默认'));
    await tester.pump();
    expect(store.activeProfileId, 'p2');

    // 删除默认项：确认后默认项清空。
    await tester.tap(find.text('删除').last);
    await _pumpFrames(tester);
    expect(find.text('确定删除「备用」吗？该操作不可撤销。'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除').last);
    await _pumpFrames(tester);

    expect(store.profiles, hasLength(1));
    expect(store.activeProfileId, isNull);
    expect(find.text('备用'), findsNothing);
  });
}
