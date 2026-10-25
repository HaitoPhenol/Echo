// ECP 命令层通用 JSON 工具。
//
// 领域序列化已下沉：日记走 `diary/diary_json.dart`、聊天走
// `services/chat_json.dart`、读数快照由 ConsoleStatsSnapshot 自己产出；
// 本文件只保留通用时间线格式（isoDate/isoDateTime/isoMonth），转发自
// `common/json_time.dart`，命令层继续从一处取通用工具。
export '../../common/json_time.dart';
