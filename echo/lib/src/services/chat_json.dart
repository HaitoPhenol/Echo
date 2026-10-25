import '../common/json_time.dart';
import 'chat_repository.dart';

/// 聊天领域的 ECP 线格式（手册 §6 chat.*）。
///
/// services 层只依赖 common 的时间工具与自身模型，不反向依赖 control。

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
