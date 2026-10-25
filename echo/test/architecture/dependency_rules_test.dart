import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R3 架构接缝：装配知识集中在 `app/app_services.dart`，各层不再各自
/// 跨域拿实例。以下断言递归扫描目录，新增文件同样受约束。
List<File> _dartFiles(String dir) {
  final files = Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();
  expect(files, isNotEmpty, reason: '从 echo/ 包目录运行测试');
  return files;
}

RegExp _banned(Iterable<String> domains) => RegExp(
  r'''import\s+['"](?:package:echo/src/|(?:\.\./)+)(?:'''
  '${domains.join('|')}'
  r''')/''',
);

void main() {
  test('services/ 源码静态约束：不 import control/diary/navigation', () {
    final banned = _banned(['control', 'diary', 'navigation']);
    for (final f in _dartFiles('lib/src/services')) {
      expect(
        banned.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} 不得反向 import control/diary/navigation（分层接缝）',
      );
    }
  });

  test('navigation/ 不 import 日记数据/UI 与具体页面实现', () {
    final banned = _banned(['pages', 'diary/data', 'diary/ui']);
    for (final f in _dartFiles('lib/src/navigation')) {
      expect(
        banned.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} 不得直接依赖日记数据/UI 或具体页面（绑定在装配根）',
      );
    }
  });

  test('diary/ 不反向 import navigation/', () {
    final banned = _banned(['navigation']);
    for (final f in _dartFiles('lib/src/diary')) {
      expect(
        banned.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} 不得反向 import navigation（几何常量已下沉 theme）',
      );
    }
  });

  test('common/ 保持中立：不 import 任何业务层', () {
    final banned = _banned([
      'app',
      'control',
      'diary',
      'navigation',
      'pages',
      'services',
    ]);
    for (final f in _dartFiles('lib/src/common')) {
      expect(
        banned.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} 是跨层共用件，不得依赖具体业务域（R5 事件总线）',
      );
    }
  });
}
