/// slash 指令态 UI（G2）桶导出。
///
/// 与 `control/slash/`（G1 纯 Dart 核心）分层：本目录允许依赖
/// Widget/Material；核心层零 Widget 红线由 G1 接缝测试继续钉死。
library;

export 'slash_command_layer.dart' show SlashCommandLayer, SlashKeyEvents;
export 'slash_console_controller.dart'
    show
        SlashConsoleController,
        PinSheetMode,
        PinSheetState,
        PendingConfirm,
        MultilineDraft;
export 'slash_result_card.dart' show SlashResultCard;
export 'slash_sheets.dart' show SlashSheetHost;
