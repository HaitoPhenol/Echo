import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/diary_repository.dart';
import '../sy/sy_zip_exporter.dart';

/// 分享通道：把打包好的 zip 交给系统分享面板。
///
/// 生产实现走 share_plus；测试注入假实现捕获 [XFile]，不碰平台通道。
typedef DiaryShareChannel = Future<void> Function(List<XFile> files);

/// 一次年导出的结果。
class DiaryExportOutcome {
  const DiaryExportOutcome({
    required this.year,
    required this.exportedCount,
    this.userDenied = false,
  });

  final int year;

  /// 本次打包并标记 exported 的篇数；0 表示当年没有 draft，
  /// 未生成 zip、未触发分享；用户在确认对话框否认发送时也是 0
  /// （此时 [userDenied] 为 true，draft 全部保留）。
  final int exportedCount;

  /// 已触发分享但用户在「确认已发送」对话框选择尚未发送：
  /// 状态未迁移，草稿可再次导出。
  final bool userDenied;

  /// 是否实际触发了分享并完成状态迁移。
  bool get didShare => exportedCount > 0;
}

/// 分享返回后的人工确认钩子（用户裁定 B）：
/// 返回 true 才把草稿迁移为 exported。
///
/// Android 的 share_plus 不回报用户是否真正发送——取消分享面板也
/// 正常完成 Future——故由 UI 弹二次确认兜底；iOS 同理保持一致交互。
typedef DiaryExportConfirm = Future<bool> Function();

/// 年行增量导出编排：取当年 draft → 打 .sy.zip → 系统分享 →
/// 用户确认已发送后批量 draft→exported。
///
/// 状态语义：分享 Future 正常完成只代表系统分享面板流程结束
/// （share_plus 平台语义，不保证对方已收到），Android 取消分享同样
/// 正常返回；故必须经 [DiaryExportConfirm] 人工确认（UI 弹对话框），
/// 用户否认则保留全部 draft、删除临时 zip，可再次导出。
/// 故名 exported——正文仍留本机只读；用户在思源确认导入后再手动归档。
/// 分享抛异常时保留全部 draft、临时 zip 不删除并上抛错误。
class DiaryExportService {
  DiaryExportService({
    required this.repository,
    DiaryShareChannel? shareChannel,
    SyZipExporter? exporter,
    Future<Directory> Function()? tempDirectory,
    DateTime Function()? now,
  }) : _share = shareChannel ?? _defaultShare,
       _exporter = exporter ?? SyZipExporter(),
       _tempDirectory = tempDirectory ?? getTemporaryDirectory,
       _now = now ?? DateTime.now;

  /// 导出笔记本名固定为「日记」（用户裁定 3.A）。
  static const String notebookName = '日记';

  final DiaryRepository repository;
  final DiaryShareChannel _share;
  final SyZipExporter _exporter;
  final Future<Directory> Function() _tempDirectory;
  final DateTime Function() _now;

  /// 导出指定年份的全部草稿。
  ///
  /// 无 draft 时返回 [DiaryExportOutcome.exportedCount] 为 0，不分享；
  /// 分享流程结束后调 [confirmShared]（生产由年列表弹「确认已发送」
  /// 对话框）：确认后才批量迁移为 exported 并删除临时 zip；否认则
  /// 保留全部 draft、清理临时 zip，返回 userDenied=true。
  /// 为 null 时默认确认（仅供测试 / 无 UI 调用方）。
  Future<DiaryExportOutcome> exportYear(
    int year, {
    DiaryExportConfirm? confirmShared,
  }) async {
    final diaries = await repository.draftDocumentsOfYear(year);
    if (diaries.isEmpty) {
      return DiaryExportOutcome(year: year, exportedCount: 0);
    }

    final exportedAt = _now();
    final bytes = _exporter.build(
      notebookName: notebookName,
      diaries: diaries,
      exportedAt: exportedAt,
    );

    final tempDir = await _tempDirectory();
    final zipFile = File(
      '${tempDir.path}/$notebookName-$year-${_stamp(exportedAt)}.sy.zip',
    );
    // flush: true 确保内容落地后再交给分享目标读取。
    await zipFile.writeAsBytes(bytes, flush: true);

    try {
      await _share([XFile(zipFile.path, mimeType: 'application/zip')]);
    } catch (_) {
      // 分享失败：draft 原样保留，临时 zip 留作排查，错误上抛。
      rethrow;
    }

    // 平台不回报真实发送结果（Android 取消也正常返回），由人工确认。
    final confirmed =
        confirmShared == null || await confirmShared();
    if (!confirmed) {
      // 用户否认：draft 全部保留以便重新打包导出；临时 zip 清掉，
      // 下次导出会以新时间戳重新生成。
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {
        // 清理失败不影响结论（系统缓存目录会自行回收）。
      }
      return DiaryExportOutcome(
        year: year,
        exportedCount: 0,
        userDenied: true,
      );
    }

    // 确认已发送后才迁移状态；markExported 整批校验，
    // 任一日期已非 draft 则整批不迁移（StateError 上抛）。
    await repository.markExported(
      diaries.map((doc) => doc.date),
      exportedAt: exportedAt,
    );
    try {
      if (await zipFile.exists()) await zipFile.delete();
    } catch (_) {
      // 临时文件清理失败不影响导出结论（系统缓存目录会自行回收）。
    }

    return DiaryExportOutcome(year: year, exportedCount: diaries.length);
  }

  /// 文件名时间戳：yyyyMMdd-HHmmss。
  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static Future<void> _defaultShare(List<XFile> files) =>
      SharePlus.instance.share(ShareParams(files: files));
}
