/// 信封 → 结构化结果视图模型（纯 Dart，与渲染无关）。
///
/// G2 搜索卡片与未来终端页（设计 §7 愿景）共用这一个接口：本文件只
/// 产出不可变的渲染描述，Widget/JSON 高亮/长按复制均由消费方实现。
///
/// 三档形态：
/// - [TableView]：`result.items` 为对象数组时成表（列＝键并集）；
/// - [KeyValueView]：对象成键值（嵌套对象递归，数组/复杂值内嵌
///   [JsonView]）；
/// - [JsonView]：兜底的缩进 JSON 文本；
/// 失败信封统一 [ErrorView]，扁平携带 need/elevate/retryAfterMs，
/// 消费方据此直接驱动 PIN 引导/冷却提示，无需解析 message 文案。
library;

import 'dart:convert';

import '../protocol/control_envelope.dart';

sealed class ResultView {
  const ResultView();
}

/// 失败视图：错误码/文案 + 结构化裁决字段。
class ErrorView extends ResultView {
  const ErrorView({
    required this.code,
    required this.message,
    this.need,
    this.elevate,
    this.retryAfterMs,
  });

  /// 有线错误码（AUTH_REQUIRED / USAGE / NOT_FOUND …）。
  final String code;
  final String message;

  /// AUTH_REQUIRED：所需级别（G2 据此判断弹解锁还是首装引导）。
  final int? need;

  /// AUTH_REQUIRED：提权命令名（auth.unlock）。
  final String? elevate;

  /// AUTH_COOLDOWN：剩余冷却毫秒。
  final int? retryAfterMs;
}

/// 表格视图（chat.list / diary.list / sys.audit 等 items 数组）。
class TableView extends ResultView {
  const TableView({required this.columns, required this.rows});

  /// 列名：全部行键的有序并集（按首次出现顺序）。
  final List<String> columns;

  /// 行值按 [columns] 对齐，缺失键为 null；单元格只放标量，复杂值
  /// 已 JSON 化为字符串。
  final List<List<Object?>> rows;
}

/// 键值对视图（status/info/get 等对象结果）。
class KeyValueView extends ResultView {
  const KeyValueView(this.entries);

  final List<KvEntry> entries;
}

class KvEntry {
  const KvEntry(this.key, this.value);

  final String key;

  /// 标量（String/num/bool/null）直接渲染；[ResultView] 为嵌套对象/
  /// 数组的子视图。
  final Object? value;
}

/// JSON 文本视图（兜底与「长按复制源」）。
class JsonView extends ResultView {
  JsonView(this.json);

  final String json;
}

/// 信封 → 视图。
ResultView viewOf(ControlEnvelope env) {
  final error = env.error;
  if (!env.ok || error != null) {
    return ErrorView(
      code: error!.code.wire,
      message: error.message,
      need: error.need,
      elevate: error.elevate,
      retryAfterMs: error.retryAfterMs,
    );
  }
  return viewOfResult(env.result ?? const {});
}

/// 仅对 result 主体建视图（help/man 等非信封场景也可复用）。
ResultView viewOfResult(Object? result) {
  if (result is Map) {
    final items = result['items'];
    if (items is List && items.every((e) => e is Map)) {
      final table = _tableOf(items.cast<Map>());
      if (table != null) return table;
    }
    return _keyValueOf(result);
  }
  return JsonView(_encode(result));
}

TableView? _tableOf(List<Map> items) {
  final columns = <String>[];
  for (final row in items) {
    for (final key in row.keys) {
      final k = key.toString();
      if (!columns.contains(k)) columns.add(k);
    }
  }
  final rows = <List<Object?>>[
    for (final row in items) [for (final c in columns) _scalarOrJson(row[c])],
  ];
  return TableView(columns: columns, rows: rows);
}

KeyValueView _keyValueOf(Map map) {
  return KeyValueView([
    for (final entry in map.entries)
      KvEntry(entry.key.toString(), _classify(entry.value)),
  ]);
}

/// 值分类：标量原样；Map 递归成子键值；List/其他 → 内嵌 JSON。
Object? _classify(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) return _keyValueOf(value);
  return JsonView(_encode(value));
}

Object? _scalarOrJson(Object? value) =>
    (value == null || value is String || value is num || value is bool)
    ? value
    : _encode(value);

String _encode(Object? value) => JsonEncoder.withIndent('  ', (Object? o) {
  // 总线结果理论上只含 JSON 原生类型；DateTime 兜底成 ISO。
  return o is DateTime ? o.toIso8601String() : o.toString();
}).convert(value);
