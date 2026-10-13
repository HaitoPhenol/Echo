import '../../services/chat_session_controller.dart';
import '../../services/chat_store.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';
import 'control_json.dart';

/// `chat` 命名空间：会话列表 / 消息分页 / 进入会话 / 外发 / 已读
/// （手册 §6，P2）。
///
/// 同路原则：`chat.open` 与 UI 点按行都只调
/// [ChatSessionController.open]；`chat.mark-read` 直接调
/// [ChatStore.markRead]；`chat.send` 与未来输入框共用 [ChatStore.send]。
List<CommandSpec> buildChatCommands() => [
  chatList,
  chatGet,
  chatOpen,
  chatSend,
  chatMarkRead,
];

/// `chat.list`：会话摘要列表（不含正文）。
final CommandSpec chatList = CommandSpec(
  namespace: 'chat',
  verb: 'list',
  summary: '会话摘要列表（不给正文）',
  kind: CommandKind.read,
  level: ControlLevel.owner,
  handler: (ctx) async {
    final store = ctx.requireService<ChatStore>('聊天服务');
    return {
      // 信封 result 必须是对象（设计 §8），故与 diary.list 同构
      // 用 items 包裹；顺序即 store 的新→旧。
      'items': store.conversations.map(chatConversationJson).toList(),
    };
  },
);

/// `chat.get`：单会话元数据 + 一条消息页（新→旧，id 游标）。
final CommandSpec chatGet = CommandSpec(
  namespace: 'chat',
  verb: 'get',
  summary: '读取单会话元数据与消息页（倒序游标分页）',
  kind: CommandKind.read,
  level: ControlLevel.owner,
  params: [
    ParamSpec('id', type: ArgType.string, required: true, summary: '会话 id'),
    ParamSpec(
      'limit',
      type: ArgType.integer,
      defaults: 20,
      summary: '每页条数（1..100）',
    ),
    ParamSpec('cursor', type: ArgType.string, summary: '上一页返回的消息 id 游标'),
  ],
  handler: (ctx) async {
    final store = ctx.requireService<ChatStore>('聊天服务');
    final id = ctx.arg<String>('id');
    final conversation = store.conversationOf(id);
    if (conversation == null) {
      throw ControlException(ControlErrorCode.notFound, '没有这个会话：$id');
    }
    // limit 越界 / 坏游标由 store 抛 ArgumentError，总线映射 USAGE。
    final page = store.messagesOf(
      id,
      limit: ctx.arg<int>('limit'),
      cursor: ctx.optionalArg<String>('cursor'),
    );
    return {
      ...chatConversationJson(conversation),
      'messages': page.items.map(chatMessageJson).toList(),
      if (page.nextCursor != null) 'cursor': page.nextCursor,
      'hasMore': page.hasMore,
    };
  },
);

/// `chat.open`：经会话控制器进入会话（与点按同路径，触发已读）。
final CommandSpec chatOpen = CommandSpec(
  namespace: 'chat',
  verb: 'open',
  summary: '进入指定会话（与点按行同路径，触发已读）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  params: [
    ParamSpec('id', type: ArgType.string, required: true, summary: '会话 id'),
  ],
  handler: (ctx) async {
    final store = ctx.requireService<ChatStore>('聊天服务');
    final controller = ctx.requireService<ChatSessionController>('会话控制器');
    final id = ctx.arg<String>('id');
    if (store.conversationOf(id) == null) {
      throw ControlException(ControlErrorCode.notFound, '没有这个会话：$id');
    }
    controller.open(id);
    // 回读 store 现状（open 已触发 markRead），便于断言未读清除。
    return chatConversationJson(store.conversationOf(id)!);
  },
);

/// `chat.send`：外发一条消息（3 级；非幂等；空文本 USAGE）。
///
/// 定级（2026-10-13 修订，设计 §5.1）：消息真实发出是外部可见、不可
/// 撤回的副作用，故为 admin 级须当次前台解锁会话；但**非破坏性**，
/// 会话内连续发送不逐条要 --confirm（显式 confirmRequired:false）。
///
/// 长文本经脚本 `--text-stdin` 注入，总线只看到合并后的 `text` 键，
/// 命令层不感知文本来源。正文在清单上标 auditRedact：审计流水只记
/// `<redacted:N>`（N 为 trim 后落库长度），成功/失败均不落字面。
final CommandSpec chatSend = CommandSpec(
  namespace: 'chat',
  verb: 'send',
  summary: '向指定会话外发一条消息（需解锁会话；非幂等）',
  kind: CommandKind.write,
  level: ControlLevel.admin,
  idempotent: false,
  // 3 级但非破坏性：解锁会话即可，不弹确认卡/不要 --confirm。
  confirmRequired: false,
  params: [
    ParamSpec('id', type: ArgType.string, required: true, summary: '会话 id'),
    ParamSpec(
      'text',
      type: ArgType.string,
      required: true,
      summary: '消息正文（trim 后不能为空）',
      auditRedact: true,
    ),
  ],
  handler: (ctx) async {
    final store = ctx.requireService<ChatStore>('聊天服务');
    final id = ctx.arg<String>('id');
    if (store.conversationOf(id) == null) {
      throw ControlException(ControlErrorCode.notFound, '没有这个会话：$id');
    }
    // 空白文本由 store 抛 ArgumentError → USAGE。
    final message = store.send(id, ctx.arg<String>('text'));
    return chatMessageJson(message);
  },
);

/// `chat.mark-read`：直接调 store 标记已读（幂等）。
final CommandSpec chatMarkRead = CommandSpec(
  namespace: 'chat',
  verb: 'mark-read',
  summary: '标记指定会话已读（幂等）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  params: [
    ParamSpec('id', type: ArgType.string, required: true, summary: '会话 id'),
  ],
  handler: (ctx) async {
    final store = ctx.requireService<ChatStore>('聊天服务');
    final id = ctx.arg<String>('id');
    if (store.conversationOf(id) == null) {
      throw ControlException(ControlErrorCode.notFound, '没有这个会话：$id');
    }
    store.markRead(id);
    return chatConversationJson(store.conversationOf(id)!);
  },
);
