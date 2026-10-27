import 'dart:io';

import 'package:echo/src/ai/ai_config.dart';
import 'package:echo/src/ai/ai_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

AiModelProfile _profile(
  String id, {
  String name = '',
  AiReasoningEffort effort = AiReasoningEffort.unspecified,
}) {
  return AiModelProfile(
    id: id,
    name: name,
    baseUrl: 'https://api.example.com/v1',
    apiKey: 'sk-secret-$id',
    model: 'model-$id',
    reasoningEffort: effort,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('echo_ai_config_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('首次保存自动设为默认，并能从私有文件回读', () async {
    final store = AiConfigStore(directory: tempDir);
    await store.load();
    expect(store.profiles, isEmpty);

    await store.upsert(_profile('p1', name: '主力'));

    expect(store.profiles, hasLength(1));
    expect(store.activeProfileId, 'p1');
    expect(
      File('${tempDir.path}/${AiConfigStore.fileName}').existsSync(),
      isTrue,
    );

    final reopened = AiConfigStore(directory: tempDir);
    await reopened.load();
    expect(reopened.profiles, hasLength(1));
    expect(reopened.profiles.single.name, '主力');
    expect(reopened.activeProfileId, 'p1');
    // API Key 明文只落在私有文件里，回读时必须保留原值（界面另做掩码）。
    expect(reopened.profiles.single.apiKey, 'sk-secret-p1');
  });

  test('新增第二条不抢默认项；可显式切换默认', () async {
    final store = AiConfigStore(directory: tempDir);
    await store.upsert(_profile('p1'));
    await store.upsert(_profile('p2'));

    expect(store.activeProfileId, 'p1');
    await store.setActive('p2');
    expect(store.activeProfileId, 'p2');

    final reopened = AiConfigStore(directory: tempDir);
    await reopened.load();
    expect(reopened.activeProfileId, 'p2');
  });

  test('删除默认项后默认项清空', () async {
    final store = AiConfigStore(directory: tempDir);
    await store.upsert(_profile('p1'));
    await store.remove('p1');

    expect(store.profiles, isEmpty);
    expect(store.activeProfileId, isNull);
  });

  test('切换不存在的默认项被忽略', () async {
    final store = AiConfigStore(directory: tempDir);
    await store.upsert(_profile('p1'));
    await store.setActive('missing');
    expect(store.activeProfileId, 'p1');
  });

  test('损坏的配置文件不会阻塞载入', () async {
    File('${tempDir.path}/${AiConfigStore.fileName}')
        .writeAsStringSync('{not-json');
    final store = AiConfigStore(directory: tempDir);

    await store.load();
    expect(store.isLoaded, isTrue);
    expect(store.profiles, isEmpty);
  });
}
