import 'package:flutter/widgets.dart';

import '../export/diary_export_service.dart';

/// 向日记子树提供唯一的 [DiaryExportService]（由 [DiaryPage] 装配）。
class DiaryExportServiceScope extends InheritedWidget {
  const DiaryExportServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final DiaryExportService service;

  /// 取服务（年列表必定在装配子树内，缺失即装配错误）。
  static DiaryExportService of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiaryExportServiceScope>();
    assert(scope != null, '子树中缺少 DiaryExportServiceScope');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(DiaryExportServiceScope oldWidget) =>
      !identical(service, oldWidget.service);
}
