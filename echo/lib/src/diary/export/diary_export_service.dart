import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/diary_repository.dart';
import '../sy/diary_model.dart';
import '../sy/sy_zip_exporter.dart';

/// 一次「只打包不分享」导出的产物信息（ECP `diary.export`）。
class DiaryZipBuild {
  const DiaryZipBuild({
    required this.path,
    required this.entries,
    required this.sizeBytes,
    required this.notebook,
  });

  /// .sy.zip 的沙盒绝对路径（不外带内容，调用方自行 pull / 分享）。
  final String path;

  /// 包内日记篇数。
  final int entries;

  final int sizeBytes;

  /// 实际使用的笔记本名（缺省回落到固定名）。
  final String notebook;
}

/// 没有任何 draft 可导出（ECP 命令据此返回业务失败，而不是生成空包）。
class DiaryExportEmptyException implements Exception {
  const DiaryExportEmptyException();

  @override
  String toString() => '没有可导出的 draft 日记';
}

/// 分享通道：把打包好的 zip 交给系统分享面板。
///
/// 生产实现走 share_plus；测试注入假实现捕获 [XFile]，不碰平台通道。
typedef DiaryShareChannel = Future<void> Function(List<XFile> files);

/// 一次**月**导出的结果。
class DiaryExportOutcome {
  const DiaryExportOutcome({
    required this.year,
    required this.month,
    required this.exportedCount,
    this.userDenied = false,
  });

  final int year;

  /// 导出月份（1..12）。
  final int month;

  /// 本次打包并标记 exported 的篇数；0 表示当月没有 draft，
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

/// 月行增量导出编排：取当月 draft → 打 .sy.zip → 系统分享 →
/// 用户确认已发送后批量 draft→exported。
///
/// 导出粒度已于 2026-10-18 由年改月（用户裁定）；包内月标签为
/// `yyyy-MM`，包名 `日记-yyyy-MM-<时间戳>.sy.zip`。
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

  /// 导出指定年月的全部草稿。
  ///
  /// 无 draft 时返回 [DiaryExportOutcome.exportedCount] 为 0，不分享；
  /// 分享流程结束后调 [confirmShared]（生产由月列表弹「确认已发送」
  /// 对话框）：确认后才批量迁移为 exported 并删除临时 zip；否认则
  /// 保留全部 draft、清理临时 zip，返回 userDenied=true。
  /// 为 null 时默认确认（仅供测试 / 无 UI 调用方）。
  Future<DiaryExportOutcome> exportMonth(
    int year,
    int month, {
    DiaryExportConfirm? confirmShared,
  }) async {
    final diaries = await repository.draftDocumentsOfMonth(year, month);
    if (diaries.isEmpty) {
      return DiaryExportOutcome(year: year, month: month, exportedCount: 0);
    }

    final exportedAt = _now();
    final bytes = _exporter.build(
      notebookName: notebookName,
      diaries: diaries,
      exportedAt: exportedAt,
    );

    final tempDir = await _tempDirectory();
    final mm = month.toString().padLeft(2, '0');
    final zipFile = File(
      '${tempDir.path}/$notebookName-$year-$mm-${_stamp(exportedAt)}.sy.zip',
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
    final confirmed = confirmShared == null || await confirmShared();
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
        month: month,
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

    return DiaryExportOutcome(
      year: year,
      month: month,
      exportedCount: diaries.length,
    );
  }

  /// 只打包、不分享、不迁移状态（ECP `diary.export` 的同路入口）：
  ///
  /// 收集 [year]（null = 全部年份）下的 draft 交给同一个
  /// [SyZipExporter] 打成一个 `.sy.zip`，写入 [outputDirectory]。
  /// 与 UI 的 [exportMonth] 区别仅在「不触发系统分享、不做 draft→
  /// exported 迁移」——分享确认流属于 UI 流程；打包链路完全一致，
  /// 因此产物可重复生成。
  ///
  /// 导出粒度已改月；[month] 可选（须与 [year] 同时给出），给出时
  /// scope 为 `yyyy-MM`，否则为 `yyyy` / `all`。
  ///
  /// [notebookName] 缺省或空白时回落 UI 固定名 [DiaryExportService
  /// .notebookName]（用户裁定：命令侧该参数可选）。无任何 draft 时
  /// 抛 [DiaryExportEmptyException]，不生成空包。
  Future<DiaryZipBuild> buildDraftZip({
    String? notebookName,
    int? year,
    int? month,
    required Directory outputDirectory,
  }) async {
    final name = (notebookName == null || notebookName.trim().isEmpty)
        ? DiaryExportService.notebookName
        : notebookName.trim();

    final diaries = <DiaryDocument>[];
    if (year == null) {
      for (final y in await repository.availableYears()) {
        diaries.addAll(await repository.draftDocumentsOfYear(y));
      }
    } else if (month == null) {
      diaries.addAll(await repository.draftDocumentsOfYear(year));
    } else {
      diaries.addAll(await repository.draftDocumentsOfMonth(year, month));
    }
    if (diaries.isEmpty) throw const DiaryExportEmptyException();

    final exportedAt = _now();
    final bytes = _exporter.build(
      notebookName: name,
      diaries: diaries,
      exportedAt: exportedAt,
    );

    await outputDirectory.create(recursive: true);
    final scope = year == null
        ? 'all'
        : (month == null
              ? '$year'
              : '$year-${month.toString().padLeft(2, '0')}');
    final zipFile = File(
      '${outputDirectory.path}/$name-$scope-${_stamp(exportedAt)}.sy.zip',
    );
    await zipFile.writeAsBytes(bytes, flush: true);
    return DiaryZipBuild(
      path: zipFile.path,
      entries: diaries.length,
      sizeBytes: bytes.length,
      notebook: name,
    );
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
