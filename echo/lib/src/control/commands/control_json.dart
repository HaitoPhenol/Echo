import '../../diary/data/diary_repository.dart';
import '../../diary/sy/diary_model.dart';
import '../../services/chat_store.dart';
import '../../services/console_stats_service.dart';

/// ECP 命令结果的统一 JSON 序列化小工具。
///
/// 为什么集中在一处：`diary.get` 与 `diary.ensure` 返回同一文档
/// 结构、列表与归档也要复用摘要结构，口径分散必然漂移。全部走
/// 本地时间 ISO 8601（手册 §1.2：时间戳不做时区换算）。

/// `YYYY-MM-DD`。
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `YYYY-MM-DDTHH:mm:ss`（本地时间，无尾缀；机器读、人也读）。
String isoDateTime(DateTime d) =>
    '${isoDate(d)}T${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';

/// `YYYY-MM`。
String isoMonth(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

/// 日记块的线格式（手册 §5 diary.get：类型/级别/底色/readonly）。
Map<String, Object?> diaryBlockJson(DiaryBlock b) => {
  'id': b.id,
  'kind': b.kind.name,
  if (b.level != null) 'level': b.level,
  'text': b.text,
  if (b.background != null) 'background': b.background,
  'readonly': b.readonly,
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

// ---- chat（手册 §6）---------------------------------------------------

/// 会话列表行（chat.list / chat.open 回包）。
///
/// 线格式字段名冻结为 title/lastPreview（UI 内部称 nickname/preview，
/// 适配层负责改名，协议不跟随 UI 措辞变化）。
Map<String, Object?> chatConversationJson(ChatConversation c) => {
  'id': c.id,
  'title': c.nickname,
  'unread': c.unread,
  'lastPreview': c.preview,
  'updatedAt': isoDateTime(c.updatedAt),
};

/// 单条消息（chat.get 消息页 / chat.send 回包）；direction 走 in/out。
Map<String, Object?> chatMessageJson(ChatMessage m) => {
  'id': m.id,
  'conversationId': m.conversationId,
  'text': m.text,
  'direction': m.direction.wire,
  'createdAt': isoDateTime(m.createdAt),
};

// ---- console（手册 §7）------------------------------------------------

/// 读数条快照（console.snapshot / console.refresh 回包）。
Map<String, Object?> consoleSnapshotJson(ConsoleStatsSnapshot s) => s.toJson();
