# Echo 当前实现现状

> 本文件是 **v0.13.0+38（main，tag `v0.13.0`，2026-10-15，
> ECP P1–P4 全部交付）时点的现状快照**，记录"今天代码实际是怎么实现的"。
> 这些不是规定——工具与手段可以换，
> 但更换时必须满足 [engineering_standards.md](engineering_standards.md)
> 的原则、通过测试与真机验收，并更新本文件。历史 patch 级变更叙述不进
> 本文件（查 git 历史与
> [archive/](archive/) 归档）。
>
> 相关：[架构与接口说明](architecture.md) ·
> [工程规范](engineering_standards.md) · [规则演进机制](governance.md) ·
> [术语表](glossary.md) · [问题清单](code_review_report.md) ·
> [日记模块技术方案](diary/flutter-tech-plan.md)

---

## 技术栈与工程

- **Flutter 3.47.6 / Dart ^3.13.5**；业务三方依赖：
  `archive`（.sy.zip 打包）、`sqflite`（日记 meta 库）、
  `path_provider`（沙盒目录）、`share_plus`（系统分享）；
  测试侧 `sqflite_common_ffi`。其余为 cupertino_icons / flutter_lints。
- 状态管理：**ChangeNotifier + InheritedNotifier**（规模够用，不引框架）。
- Android 原生侧主源集 `MainActivity.kt` 两个 MethodChannel：
  `echo/haptics`（直接驱动 Vibrator，带振幅降级，声明 VIBRATE 权限）、
  `echo/device_stats`（电池温度/瞬时功率/型号/版本/flavor，零权限粘性广播）。
  **debug 源集另有 ECP 三件套**（release 物理不打包，aapt2 已验证）：
  `DebugEchoApp`（Application，反射缓存当前引擎）、
  `DebugControlReceiver`（exported 广播接收器，goAsync 转
  `echo/control` MethodChannel）、debug Manifest（tools:replace
  application name + INTERNET 权限）。
- lint：flutter_lints 默认集；**无 CI**（门禁靠本地 `flutter analyze` +
  `flutter test` 自觉执行）。
- **发布配置**：release 用 debug 签名（独立 keystore 仍待定）；
  **已开 R8**（`isMinifyEnabled`/`isShrinkResources` + 保底
  `proguard-rules.pro`）；**已接全局崩溃钩子**（`runZonedGuarded` +
  `FlutterError.onError`，保留默认输出并 `debugPrint` 标记，无远端上报后端）。
  release 包人工裁剪检查已随 P3/P4 发布常态化（dex 字符串扫描 +
  slash 补全计数 + 全新装走查，见问题清单 G8）。

## 页面与导航

横向 4 页固定（`navigation/nav_destination.dart` 的
`buildDefaultDestinations()`，稳定 id）：

| 序 | id | 页名 | 实现 |
|---|---|---|---|
| 0 | console | **终端** | TemplatePage + debug 面板（3 按钮，仅 debug） |
| 1 | chat | **聊天** | 真实 `ChatPage`：会话列表、左滑操作、未读绿点 |
| 2 | notes | **笔记** | **真实日记模块**（见下节；2026-10-10 起替换纯模板页） |
| 3 | me | **主页** | TemplatePage |

- 主屏 `SmartNavScreen`（1353 行；2026-10-16 结构债务 A 项 G1 后：
  几何纯函数收敛至 `navigation/dock_layout.dart`，手势记录类/涟漪移出
  为独立文件，`build()` 子树抽为私有构建方法）一次性常驻构建全部页面
  （Row + Stack），
  **日记页 State 常驻**：进模块自动成稿、防抖 flush 等生命周期挂在该
  常驻 State 上——改懒加载前必须先迁移这些假设。
- 导航物理为自研 `NavPhysicsController`（position 线性物理 +
  displayPosition 橡胶带/Hermite 双层）；几何单一事实来源
  `DockGeometry`（静态常量+MediaQuery，不用 GlobalKey）。
- 底部三条：把手（竖单/右拖抽屉）、AI 虹彩条（长按弹空壳对话框）、
  导航条（横滑/圆点/双击/上甩快捷弧/长按搜索）。全部手势的坐标、
  死区、互斥与返回键顺序详见
  [usage-guide.md](usage-guide.md)（操作细节以该文件为准）。
- 机能风视觉层（v0.6.0 转正，RCR-2026-001）：固定网格/点阵背景、
  顶部读数条、空心大页码、3D 转鼓、衬线页名牌；代码在
  `navigation/widgets/mechanical_*.dart`，token 在
  `theme/app_colors.dart` + `mechanical_style.dart`。
- 浮层（竖单/AI 对话框/抽屉/搜索/快捷弧）同屏至多一个，返回键统一拦截。
- debug 面板（模拟聊天新消息/模拟异常/处理异常）仅挂终端页，
  `kDebugMode` 守卫，release 树摇移除。

## 日记模块（笔记页，M1–M5 已交付）

模块文档：[diary/flutter-tech-plan.md](diary/flutter-tech-plan.md)；
思源格式：[diary/sy-format-golden-3.8.6.md](diary/sy-format-golden-3.8.6.md)。
代码在 `lib/src/diary/`：

| 子目录 | 职责 |
|---|---|
| `sy/` | 思源格式层：`DiaryDocument` 模型、确定性 ID 生成器、子集序列化器、.sy.zip 打包 |
| `data/` | `DiaryRepository` 抽象 + 内存实现 / **sqflite 持久实现**、`DiaryClock`（04:00 日界）、`DiaryDataProvider`（现为 Fake 常量）、debug 种子 |
| `template/` | 模板 JSON 解析、每日成稿 `DiaryComposer`（幂等/并发去重/快照填充） |
| `editor/` | 分块编辑器：命令、控制器（50 步撤销重做）、块视图、块标浮层 |
| `export/` | 导出服务（年行增量导出 .sy.zip） |
| `ui/` | 年→月→日浏览页、日记编辑页、三态 UI、心情选择、分享确认流 |

- **生产装配用持久仓储**（M5 起）：sqflite 库
  `<app_flutter>/echo_diary/diary.db`（diary_meta 单表：状态/时间戳/
  title/preview/block_count 反范式），正文
  `diary/{yyyy}/{mm}/{docId}.sy` 原子写（tmp+rename）。
- **三态**：`draft`（可写）/ `exported`（只读横幅）/ `archived`
  （删文件留 meta、列表弱化）。
- **自动成稿**：进笔记页 bootstrap 时 `ensureDay(clock.today())`，
  模板六块骨架（data 块深蓝底只读 + ↻ 刷新 +「（示例数据）」）；
  月页「+」补记，日期选择器禁未来日。
- **04:00 日界**：`DiaryClock.diaryDate`，hour<4 归前一自然日；
  测试注入时钟，生产取墙钟。
- **空稿清理**：进模块 prune 早于今天的空草稿（meta+.sy 双删）。
- **导出**：share_plus 调系统分享；Android 思源不响应 ACTION_SEND，
  实际走思源内 SAF 导入；分享返回后人工「确认已发送」才置 exported。
- debug 包空库灌种子两篇（上月 28 日 + 昨天，今天不种）；
  release 空仓。测试可注入仓储/时钟。

## ECP 控制面（P1–P4 已全部交付，v0.13.0）

设计 [ecp/ecp-design.md](ecp/ecp-design.md)、命令契约手册
[ecp/ecp-commands.md](ecp/ecp-commands.md)；代码在 `lib/src/control/`。
四期施工/复审流水归档于 [archive/ecp-p1-p4-review-log.md](archive/ecp-p1-p4-review-log.md)。

- **协议**：信封（ok/cmd/ms/result|error/nonce，P4 起 slow 命令首包
  可带 `async/jobId`）、错误码→进程退出码映射、`CommandSpec` 冻结
  动词表、`ControlBus`（注册重名检查、参数解析、级别/确认裁决、
  ≥2 级审计、slow 60s 预算标记）。
- **鉴权**：PIN 只存 PBKDF2 加盐哈希（`echo_control/pin.json`）；
  通道起始级别 mcp=0/adb=2、slash=2，adb/slash 解锁升 3 级，
  mcp 永不解锁（上限 1 只读）；连续 5 次错误冷却
  （30/60/120/240s/5min 退避）；App paused（息屏/切后台）立即
  销毁全部会话；审计不记 PIN 与正文（正文命令标 auditRedact，
  记 `<redacted:N>`）。
- **命令域（35 条；release 物理裁掉 5 条 debugOnly 后 30 条）**：
  sys 9（ping/help/info/status/audit/events/job.get +
  debugOnly clock.set/delay）、auth 4、nav 2、diary 7
  （list/get/ensure/prune/export + debugOnly reset/seed）、
  chat 6（list/get/open/send/mark-read + debugOnly seed）、
  console 2、badge 5。
- **slash 指令台（P3）**：搜索栏 `/` 进入，三段补全（命名空间→
  动词→参数）、结果卡片、PIN/确认卡、命令历史；核心
  `control/slash/ControlConsoleCore` 与入口 Widget 解耦，终端页
  是未来第二个消费者（接缝未建页）。
- **事件流（P4）**：`events/` 内存环（256、seq 单调）+
  `sys.events` 游标/长轮询（wait≤8s，事件即唤醒）；五种冻结
  事件 audit.entry/command.finished（owner 级）、
  diary.export.completed（user 级）、chat.incoming（owner 级）、
  nav.changed（guest 级）；services 层零 control 反向依赖，
  ChatStore 自有 incoming Stream 经 `ControlEventBridge` 适配转发。
- **作业化执行（P4，根治接收器 9s 预算）**：slow 命令仅 adb 通道
  立即回 async running，后台跑（`jobs/` 环 32、跨通道隔离），
  `sys.job.get` 轮询终态；轮询走普通广播，**Kotlin 零改动**；
  slash 通道行为不变（进程内直等终态）。
- **同路装配**：`ControlBootstrap.init()` 在 main() 内 await
  （建 echo_control 目录、注册常驻服务）；导航屏注册
  NavPhysicsController，日记页 bootstrap 注册与 UI 同源的
  clock/仓储/composer/导出服务；未注册时命令回 CONFLICT。
- **工作站入口**：`scripts/echo-cmd <命令>`（冷启动轮询 ping、
  kebab→camel 参数、stdin 收 PIN 不进历史、退出码对齐手册；
  P4 起 slow 命令默认自动轮询终态最长 65s，`--no-wait` 只取
  running）。脚本级回归 `scripts/tests/echo_cmd_test.sh`
  （fake-adb，15 断言，无需设备）。
- **门禁**：`test/control/` 协议/鉴权/四域/slash/事件/作业/播种/
  MCP 假通道边界 + manifest↔手册双向一致性；MIX 2S 每期真机
  验收（P4：delay 12s 首包 11ms、导出落盘、事件提前唤醒、
  seed→prune/seed→send 端到端、slash 回归），release dex 六串
  全 0、补全计数 sys7/diary5/chat5。

## 状态与服务

- `ChatStore`（services/，ChangeNotifier + Scope）：内存会话列表，
  新消息/删除/已读/未读，`hasUnread` 聚合；重启清空。聊天锚点数据
  驱动（全部会话已读才恢复），其余页停留 700ms 已读。
- `InMemoryNavBadgeService`：锚点三态（正常/通知/异常），**按目的地
  稳定 id（`NavDestination.id`）索引**（2026-10-16 结构债务 A 项 G5
  已替换原页序 int 索引，为持久化铺路；未知 id 读返 normal、写忽略）。
- `SearchService`：多 Provider 聚合搜索；当前仅"页面搜索"一个源，
  同步接口；历史为内存实现。
- 日记仓储单例在 `DiaryPage` bootstrap 打开（debug 自动成稿+种子），
  测试/装配可注入。

## 平台与适配

- 主验证设备：Android 真机（MIX 2S，1080×2160/440dpi，MIUI）；
  **形态裁定（Q2，2026-10-16）：手机锁竖屏、平板不锁方向**。
  锁向已落地（`MainActivity.onCreate` 按 `smallestScreenWidthDp≥600`
  区分 `requestedOrientation`：手机 PORTRAIT、平板 UNSPECIFIED；MIX 2S
  真机取证 `mCurrentAppOrientation=SCREEN_ORIENTATION_PORTRAIT`）；平板/折叠
  横屏与大屏 UI 适配暂不做——当前无 LayoutBuilder/断点/宽度钳制，大屏上是
  "被拉宽的竖版"，不承诺体验。
- 文案仅中文硬编码，无 l10n；**无障碍已做最小集 Semantics**（底栏导航条
  label/value + `onIncrease/onDecrease` 翻页动作，两端圆点/把手/AI/快捷弧/
  会话行及左滑两按钮加按钮语义，机能风五个纯装饰层 `ExcludeSemantics`；
  圆点/把手/AI/快捷弧的激活动作留待后续按需接线）。
- Impeller 注记：MIX 2S + Flutter 3.47.6 横向滚筒非当前槽位首帧偶发
  白屏，息屏亮屏重建 surface 恢复，与业务代码无关。

## 测试现状

- **445 个 Dart 测试，43 个文件** + echo-cmd 脚本级回归 15 断言：
  - `test/widget_test.dart`（导航/浮层集成）、
    `navigation/`（几何纯函数）、`pages/`（聊天交互）、
    `services/`（触感通道异常降级等）；
  - `test/diary/`：sy 格式层金标准、ID、序列化往返、zip 打包、
    时钟边界、内存/持久仓储、成稿器、编辑器命令/控制器、
    导出服务、年日月浏览 widget、M5 三态/分享流/崩溃恢复；
  - `test/control/`：总线注册/解析/审计脱敏与**过鉴权后
    失败/超时入审计（E3）**、鉴权矩阵
    （通道×级别/退避/前后台即焚/PinStore 规则）、七域命令、
    slash 解析/补全/控制台核心、事件环/长轮询/五事件集成、
    作业轮询/跨通道隔离、播种端到端、MCP 假通道只读边界、
    manifest↔命令手册双向一致性；
  - 另有 testDebug JVM 单测 3 条（接收器 0/2000 uid 白名单，E1）。
- 动画用例逐帧 pump、不用 pumpAndSettle（常驻循环动画）；
  持久仓储测试用 FFI 工厂 + 临时目录。
- 真机回归：M1 格式包思源 3.8.6 导入通过；M2–M5 每个里程碑
  MIX 2S 真机验收（见 tech-plan 里程碑表）；ECP P1–P4 每期
  debug+release 双包真机终审（见
  [archive/ecp-p1-p4-review-log.md](archive/ecp-p1-p4-review-log.md)）。
- 待补：M6 ≥2 台真机连写 7 天。

## 已知问题与待决策

见 [code_review_report.md](code_review_report.md)：日记线 D1–D7
（真实数据源、空稿标注回归、Slash 菜单、mood 桥接等）、
通用工程 G1–G13、待拍板 Q3/Q4/Q5/Q6/Q8（Q2 设备形态已决）。

**本文件的维护规则**：实现手段变化并合并后，立即更新对应条目并在提交
信息中说明；问题修复后从问题清单移除，不要让本文件描述已经不存在的现状。
