/// 日记内层导航的编程式接口（ECP `diary.goto` 的同路入口）。
///
/// 日记模块自带一个内层 Navigator（年→月→日→编辑页四级栈），运行在
/// widget 树内。控制面（adb 广播 / slash / 未来 MCP）在树外，故本接口
/// 只声明「跳到哪一层」的语义，由 [DiaryPageState] 实现并注册进
/// ECP 服务注册表；命令层经注册表取用，不直接触达任何 Widget。
///
/// **纯 Dart 接口**：不 import 任何 Flutter 类型，控制层可安全引用，
/// 不破坏「services/navigation 层零 control 依赖」的反向纪律。
///
/// 日期约束与模块一致：目标日期不得晚于日记日时钟的「今天」
/// （M4 不提供未来日期入口）；越界判定收口在命令层，本接口假设
/// 调用方已完成校验。
abstract class DiaryNavigatorController {
  /// 回到根（年列表）。
  Future<void> showYearList();

  /// 跳到某年的月份列表。
  Future<void> showMonthList(int year);

  /// 跳到某年某月的日列表。
  Future<void> showDayList(int year, int month);

  /// 跳到某日的编辑页（栈形态与手动「年→月→日」进入一致：
  /// 年列表 → 该月月列表 → 该月日列表 → 该日编辑页）。
  Future<void> showEditor(DateTime date);
}
