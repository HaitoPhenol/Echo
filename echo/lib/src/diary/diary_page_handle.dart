/// 日记页对导航屏暴露的内层能力。
///
/// navigation 只依赖本抽象，不 import `diary/ui` 具体页面；实现由
/// `DiaryPageState` 提供，装配根经回调把当前 State 交给导航屏。
abstract interface class DiaryPageHandle {
  /// 栈顶是否为可写的日编辑页（竖单据此显示「插入时间戳」）。
  bool get isEditorPage;

  /// 在编辑页光标所在块的下一行插入一个时间戳段；无可用编辑页返回 false。
  bool insertStampBelowCursor();

  /// 把日记内层栈带到今日编辑页。
  void openTodayEditor();

  /// 弹日期选择器补记过去某天。
  Future<void> startBackfill();

  /// 冷启动首次进笔记页时请求一次导出提醒（数据驱动判定）。
  Future<void> maybeShowExportReminder();
}
