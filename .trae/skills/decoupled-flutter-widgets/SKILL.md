---
name: decoupled-flutter-widgets
description: Echo 项目多形态组件与开合动画的实施速查。用户要求组件解耦、留接口，或反馈动画卡顿/穿帮/边框圆角异常时使用；纯静态 UI 微调不用。
---

# 解耦组件与开合动画（实施速查）

原则与事故机理见 `docs/engineering_standards.md` 1.6~1.12 及第 3 节
事故 1/3/11/12/13/14，本技能只放动手时的检查点与项目特定事实。

## 多形态组件

- 一形态一组件；编排组件持状态位、同帧交接。搜索开合的现成模式
  （search_capsule.dart，案例 commit aea128c）：`_showNav`（真实导航条
  仅常规态挂载）/ `_keepPill`（关闭动画播完才卸载 pill）/ `_opening`
  （方向位；收回时滑块锚点恒不参与）。
- pill 起始帧必须与导航条外观完全一致（圆点+tone1+滑块/锚点）。
- 跨组件只走构造参数/回调；ChangeNotifier 值由父级 build 时捕获为
  不可变字段下传，不读子组件内部状态。

## 动画检查点

- 条件插入 Stack/Row 的常驻节点必须带稳定 Key。
- 多 Controller 用 TickerProviderStateMixin；`didUpdateWidget` 不读
  Notifier 现值（新旧都拿到现值）。
- 帧外回调不读帧时间戳，基准在生效后首个物理帧惰性记录。
- 逐帧只动 transform/opacity：形状层用无子女轻量色块；文本等内容放
  固定目标尺寸的 Positioned 层，ClipRRect 裁溢出；整块包 RepaintBoundary。
- 描边/阴影画在 ClipRRect **之外**（线跨盒缘，在内会被裁细）。
- 圆角每帧显式 `clamp(0, frameWidth/2 - inset)`，不传 999
  （渲染器横纵独立夹取会出椭圆角）。
- **胶囊端弧与端内圆按钮必须同心**：端弧半径 = 胶囊宽 / 2、圆心在
  端边内 w/2 处；故端按钮圆心到端边也要等于 w/2，即边缘留白 =
  `(胶囊宽 − 按钮直径) / 2`，且横纵留白同值。留白写死成固定 px
  （如原型的 12px）会让端头在按钮外多突出一截。竖单案例见
  `DockGeometry.menuEdgeInsetFor`，涟漪圆心共用同一几何。
- 循环光效必须挂 AnimatedBuilder 逐帧订阅。

## 项目视觉事实（勿再试错）

- 滑块按下**无外观变化**，State 里不留按压字段；圆点按下 tone1→tone2。
  变黑/描边/近黑按压方案均已被用户否决（事故 14）。
- 被遮挡元素常挂载、画在不透明前景下层做物理遮挡，不写位置显隐。
- 滑块填充 `_thumbFill = 0xFF838383`（tone1+tone2 合成白量 0.513 的
  不透明灰）；勿用 0x83FFFFFF——外观相同但半透明挡不住锚点。
- 融入用同色：锚点常态 tone2、不发光。单一用途的颜色就地解决，
  不改共享色板常量。

## 验证

- analyze 零问题、test 全过；时间相关用 `pump()` 手动推进，不用 pumpAndSettle。
- 卡顿实测：`adb shell dumpsys gfxinfo <pkg> reset` → 触发动画 →
  再查一次，看 Janky frames / Missed Vsync（screenrecord 自身有负载，
  是最差工况；部分 MIUI Total frames 显示 0 是系统怪癖）。
- 真机抽帧确认唤起无跳变、中间帧存在、收回无穿帮。
- 只 format 本次改动文件，`git diff --stat` 确认无无关噪音。
