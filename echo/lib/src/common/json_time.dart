// ECP 线格式的统一时间序列化小工具。
//
// 放在 common/ 而非命令层：控制命令与各领域（日记/聊天）的 JSON 表达
// 都要用同一套口径，领域层不应反向依赖 control。全部走本地时间
// ISO 8601（手册 §1.2：时间戳不做时区换算）。

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
