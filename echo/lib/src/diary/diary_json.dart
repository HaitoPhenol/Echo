import '../common/json_time.dart';
import 'data/diary_repository.dart';
import 'sy/diary_model.dart';

/// 日记领域的 ECP 线格式（手册 §5 diary.*）。
///
/// 序列化随领域走：命令层只调用这些函数，不再持有日记模型结构；
/// 字段名与顺序冻结，改协议先改手册。

/// 日记块的线格式（手册 §5 diary.get：类型/级别/底色）。
///
/// 2026-10-18 模板重设后 data 只读块退役，线格式同步删 `readonly` 字段
/// （不再存在只读块，块级只读由文档级 `locked` 统一表达）。
Map<String, Object?> diaryBlockJson(DiaryBlock b) => {
  'id': b.id,
  'kind': b.kind.name,
  if (b.level != null) 'level': b.level,
  'text': b.text,
  if (b.background != null) 'background': b.background,
  'updatedAt': isoDateTime(b.updatedAt),
};

/// 完整日记文档（diary.get / diary.ensure 的 document 字段）。
///
/// [filePath] 仅当仓储有文件根（持久仓储）时给出；archived 正文已
/// 物理清除，blocks/filePath 为 null。
Map<String, Object?> diaryDocumentJson(
  DiaryDocument doc,
  DiaryDocState state, {
  String? filePath,
}) => {
  'id': doc.id,
  'title': doc.title,
  'date': isoDate(doc.date),
  'state': state.name,
  'custom': doc.custom,
  'blocks': doc.blocks.map(diaryBlockJson).toList(),
  'filePath': filePath,
  'updatedAt': isoDateTime(doc.updatedAt),
};

/// 列表行摘要（diary.list）；archived 的 title/updatedAt 为归档前快照。
Map<String, Object?> diarySummaryJson(DiaryDaySummary s) => {
  'date': isoDate(s.date),
  'title': s.title,
  'state': s.state.name,
  'preview': s.preview,
  'blockCount': s.blockCount,
  'updatedAt': isoDateTime(s.updatedAt),
};
