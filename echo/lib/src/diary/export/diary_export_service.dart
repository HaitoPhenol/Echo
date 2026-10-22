import 'dart:io';

import 'package:flutter/services.dart';
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

/// 导出渠道：交给系统分享面板，或另存到用户选定的位置。
enum DiaryExportChannel { share, save }

/// 另存通道：把打包好的临时 zip 写到用户通过系统「保存到」对话框
/// 选定的位置。
///
/// 返回 true 表示已写入（可据此直接迁移 exported），false 表示用户
/// 取消或写入失败。生产实现走 Android `echo/files` 通道（SAF），
/// 测试注入假实现，不碰平台通道与文件系统选择器。
typedef DiarySaveChannel =
    Future<bool> Function(String sourcePath, String suggestedName);

/// 一次导出（年或月）的结果。
class DiaryExportOutcome {
  const DiaryExportOutcome({
    required this.year,
    this.month,
    required this.exportedCount,
    int? markedCount,
    this.todayKeptCount = 0,
    this.channel = DiaryExportChannel.share,
    this.userDenied = false,
  }) : markedCount = markedCount ?? exportedCount;

  final int year;

  /// 导出月份（1..12）；null 表示年粒度（全年）。
  final int? month;

  /// 本次打包进 zip 的篇数（含已导出内容）；0 表示该范围没有可导出的
  /// 日记，未生成 zip、未走任何渠道；分享否认 / 另存取消时也是 0
  /// （此时 [userDenied] 为 true，草稿全部保留）。
  final int exportedCount;

  /// 本次真正迁移为 exported 的篇数。今日（未结束）的草稿会打进 zip
  /// 但保持 draft 可继续写，故可能小于 [exportedCount]（2026-10-22 用户裁定）。
  final int markedCount;

  /// 本次入包但按规则保持草稿的今日篇数（用于完成文案）。
  final int todayKeptCount;

  /// 本次实际使用的渠道（决定 UI 的完成文案）。
  final DiaryExportChannel channel;

  /// 已走所选渠道但用户否认发送 / 取消另存：状态未迁移，
  /// 草稿可再次导出。
  final bool userDenied;

  /// 是否已通过所选渠道送出（打包内容非空即视为送出）。
  bool get didExport => exportedCount > 0;

  /// 是否年粒度（全年导出）。
  bool get isYear => month == null;

  /// 导出范围提示文案（`2026 年` / `2026 年 10 月`）。
  String get scopeLabel =>
      month == null ? '$year 年' : '$year 年 $month 月';
}

/// 分享返回后的人工确认钩子（用户裁定 B）：
/// 返回 true 才把草稿迁移为 exported。
///
/// Android 的 share_plus 不回报用户是否真正发送——取消分享面板也
/// 正常完成 Future——故由 UI 弹二次确认兜底；iOS 同理保持一致交互。
typedef DiaryExportConfirm = Future<bool> Function();

/// 年 / 月范围导出编排：按范围取**全部可打包**日记（draft + exported）
/// → 打 .sy.zip → 所选渠道送出 → （分享）用户确认已发送 / （另存）
/// 写入成功 → 把范围内早于今天的 draft 批量 draft→exported。
///
/// 导出粒度由页面层级决定（2026-10-22 用户裁定）：年列表点导出为全年，
/// 月列表点导出为当月。**已导出内容也完整重新打包**（同一裁定），
/// 只有正文已清除的 archived 不参与。
///
/// 渠道语义（2026-10-22 用户裁定）：点击导出先选「分享 / 另存」。
/// 分享走系统面板，平台不回报真实发送结果（Android 取消也正常返回），
/// 故必须经 [DiaryExportConfirm] 人工确认，否认则保留全部 draft；
/// 另存走系统「保存到」对话框，能明确回报成功/取消，保存成功即直接
/// 迁移 exported，取消则保留全部 draft。
/// 故名 exported——正文仍留本机只读；用户在思源确认导入后再手动归档。
/// 渠道抛异常时保留全部 draft、临时 zip 不删除并上抛错误。
class DiaryExportService {
  DiaryExportService({
    required this.repository,
    DiaryShareChannel? shareChannel,
    DiarySaveChannel? saveChannel,
    SyZipExporter? exporter,
    Future<Directory> Function()? tempDirectory,
    DateTime Function()? now,
  }) : _share = shareChannel ?? _defaultShare,
       _save = saveChannel ?? _defaultSave,
       // 导出编码需要生成超级块/合成胶囊段 ID，注入与仓储同源的 ID 源，
       // 避免与既有块 ID 冲突（plan H 节）。
       _exporter =
           exporter ?? SyZipExporter(idGenerator: repository.idGenerator),
       _tempDirectory = tempDirectory ?? getTemporaryDirectory,
       _now = now ?? DateTime.now;

  /// 导出笔记本名固定为「日记」（用户裁定 3.A）。
  static const String notebookName = '日记';

  /// 另存通道的 Android 侧方法通道（ACTION_CREATE_DOCUMENT，跳过
  /// 第三方插件；Android 的 file_selector 不支持保存位置选择）。
  static const MethodChannel _filesChannel = MethodChannel('echo/files');

  final DiaryRepository repository;
  final DiaryShareChannel _share;
  final DiarySaveChannel _save;
  final SyZipExporter _exporter;
  final Future<Directory> Function() _tempDirectory;
  final DateTime Function() _now;

  /// 导出指定年月（该月全部可打包日记）。
  ///
  /// [channel] 为 [DiaryExportChannel.share] 时在分享流程结束后调
  /// [confirmShared]（生产由 UI 弹「确认已发送」对话框），确认后才
  /// 批量迁移为 exported；为 [DiaryExportChannel.save] 时保存成功即迁移，
  /// [confirmShared] 不参与。
  ///
  /// **今日（未结束）的日记仍打进 zip，但不迁移状态**（2026-10-22 用户
  /// 裁定）：当天还在写，导出后应保持 draft 可继续编辑；下次导出会再次
  /// 打包当日内容，直到它变成已结束日期。
  Future<DiaryExportOutcome> exportMonth(
    int year,
    int month, {
    DiaryExportChannel channel = DiaryExportChannel.share,
    DiaryExportConfirm? confirmShared,
  }) => _export(year, month, channel: channel, confirmShared: confirmShared);

  /// 导出指定年份（该年全部可打包日记，供年列表导出入口）。
  ///
  /// 包名 `日记-<年>-<时间戳>.sy.zip`，动作与迁移规则同 [exportMonth]。
  Future<DiaryExportOutcome> exportYear(
    int year, {
    DiaryExportChannel channel = DiaryExportChannel.share,
    DiaryExportConfirm? confirmShared,
  }) => _export(year, null, channel: channel, confirmShared: confirmShared);

  Future<DiaryExportOutcome> _export(
    int year,
    int? month, {
    DiaryExportChannel channel = DiaryExportChannel.share,
    DiaryExportConfirm? confirmShared,
  }) async {
    // 全量打包：draft + exported（2026-10-22 用户裁定）；archived 无正文。
    final diaries = month == null
        ? await repository.documentsOfYear(year)
        : await repository.documentsOfMonth(year, month);
    if (diaries.isEmpty) {
      return DiaryExportOutcome(
        year: year,
        month: month,
        exportedCount: 0,
        channel: channel,
      );
    }

    // 只有 draft 参与状态迁移；今日草稿入包但保持可编辑。
    final drafts = month == null
        ? await repository.draftDocumentsOfYear(year)
        : await repository.draftDocumentsOfMonth(year, month);
    final today = repository.today();
    final markable = drafts.where((doc) => doc.date.isBefore(today)).toList();
    final todayKept = drafts.length - markable.length;

    final exportedAt = _now();
    final bytes = _exporter.build(
      notebookName: notebookName,
      diaries: diaries,
      exportedAt: exportedAt,
    );

    final tempDir = await _tempDirectory();
    final scope = month == null
        ? '$year'
        : '$year-${month.toString().padLeft(2, '0')}';
    final zipName = '$notebookName-$scope-${_stamp(exportedAt)}.sy.zip';
    final zipFile = File('${tempDir.path}/$zipName');
    // flush: true 确保内容落地后再交给分享目标 / 另存读取。
    await zipFile.writeAsBytes(bytes, flush: true);

    if (channel == DiaryExportChannel.save) {
      // 另存有明确结果：保存成功即视为已导出，取消则原样保留草稿。
      final saved = await _save(zipFile.path, zipName);
      if (!saved) return _denied(year, month, channel, zipFile);
    } else {
      try {
        await _share([XFile(zipFile.path, mimeType: 'application/zip')]);
      } catch (_) {
        // 分享失败：draft 原样保留，临时 zip 留作排查，错误上抛。
        rethrow;
      }

      // 平台不回报真实发送结果（Android 取消也正常返回），由人工确认。
      final confirmed = confirmShared == null || await confirmShared();
      if (!confirmed) return _denied(year, month, channel, zipFile);
    }

    // 渠道完成且确认后才迁移状态；markExported 整批校验，
    // 任一日期已非 draft 则整批不迁移（StateError 上抛）。
    if (markable.isNotEmpty) {
      await repository.markExported(
        markable.map((doc) => doc.date),
        exportedAt: exportedAt,
      );
    }
    try {
      if (await zipFile.exists()) await zipFile.delete();
    } catch (_) {
      // 临时文件清理失败不影响导出结论（系统缓存目录会自行回收）。
    }

    return DiaryExportOutcome(
      year: year,
      month: month,
      exportedCount: diaries.length,
      markedCount: markable.length,
      todayKeptCount: todayKept,
      channel: channel,
    );
  }

  /// 用户在所选渠道中止（分享否认发送 / 另存取消）：草稿全部保留以便
  /// 重新导出，临时 zip 清掉，下次导出以新时间戳重新生成。
  Future<DiaryExportOutcome> _denied(
    int year,
    int? month,
    DiaryExportChannel channel,
    File zipFile,
  ) async {
    try {
      if (await zipFile.exists()) await zipFile.delete();
    } catch (_) {
      // 清理失败不影响结论（系统缓存目录会自行回收）。
    }
    return DiaryExportOutcome(
      year: year,
      month: month,
      exportedCount: 0,
      channel: channel,
      userDenied: true,
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
  /// [date] 为日粒度（2026-10-19 新增，ECP `diary.export --date` 用）：
  /// 给出时只打包该日 draft，scope 为 `yyyy-MM-dd`，且与 [year]/[month]
  /// 互斥（同时给出由命令层先行拦截，此处 date 优先）。
  ///
  /// [notebookName] 缺省或空白时回落 UI 固定名 [DiaryExportService
  /// .notebookName]（用户裁定：命令侧该参数可选）。无任何 draft 时
  /// 抛 [DiaryExportEmptyException]，不生成空包。
  Future<DiaryZipBuild> buildDraftZip({
    String? notebookName,
    int? year,
    int? month,
    DateTime? date,
    required Directory outputDirectory,
  }) async {
    final name = (notebookName == null || notebookName.trim().isEmpty)
        ? DiaryExportService.notebookName
        : notebookName.trim();

    final diaries = <DiaryDocument>[];
    if (date != null) {
      final day = DateTime(date.year, date.month, date.day);
      // 与 UI 同口径：只有 draft 入包，exported/archived 不重复导出。
      if (await repository.stateOfDay(day) == DiaryDocState.draft) {
        final doc = await repository.findDay(day);
        if (doc != null) diaries.add(doc);
      }
    } else if (year == null) {
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
    final scope = date != null
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}'
        : (year == null
              ? 'all'
              : (month == null
                    ? '$year'
                    : '$year-${month.toString().padLeft(2, '0')}'));
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

  /// 默认另存通道：Android 侧走 ACTION_CREATE_DOCUMENT（SAF），由用户
  /// 选目录与文件名，无需存储权限；返回 false 表示用户取消。
  ///
  /// 传临时文件路径而非字节，大包不在通道里搬运。
  static Future<bool> _defaultSave(
    String sourcePath,
    String suggestedName,
  ) async {
    final saved = await _filesChannel.invokeMethod<bool>('saveFile', {
      'sourcePath': sourcePath,
      'fileName': suggestedName,
      'mimeType': 'application/zip',
    });
    return saved ?? false;
  }
}
