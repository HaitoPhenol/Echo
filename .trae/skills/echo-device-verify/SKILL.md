---
name: echo-device-verify
description: Echo Flutter 改动的真机验证闭环——门禁、装机、adb 录屏/截图、ffmpeg 抽帧自检。用户要求真机验证、录屏看动画效果、夜间盲跑自检时使用；纯静态代码改动不用。发飞书汇报走 echo-remote-report。
---

# Echo 真机验证闭环

改动涉及动画/交互/布局、需要真机证据时使用。本技能只管**到自检证据为止**；
把证据发给用户走 `echo-remote-report`（录屏直发 media，不要发抽帧拼图）。

固定事实：仓库根 `Echo/`，Flutter 工程在 `echo/` 子目录；测试机小米 MIX 2S，
adb id `3f6cc09b`，1080×2160，density 440，包名 `com.everse.echo`，
启动 Activity `com.everse.echo/.MainActivity`。

## 1. 门禁（每次提交前必过）

```bash
cd echo && flutter analyze && flutter test
```

analyze 必须零 issue，测试必须全过（当前 24 个）。改了渲染结构后若测试报
"A Stack requires bounded constraints"，通常是 Stack 子节点全被
Positioned 包了——留一个非定位子定尺寸。

## 2. 装机

**先唤醒屏幕**：为防 OLED 烧屏，测试机不设常亮（不用 `svc power stayon`、
不改 `screen_off_timeout`），闲置即息屏；息屏后 input 事件照常执行但
screenrecord 会录到黑屏。每条调试/录屏命令前自行唤醒：

```bash
adb -s 3f6cc09b shell input keyevent KEYCODE_WAKEUP
# 无锁屏密码；若停在锁屏，上滑即可：
adb -s 3f6cc09b shell input swipe 540 1800 540 600 200
# 状态确认：Awake/Asleep 与是否在锁屏
adb -s 3f6cc09b shell dumpsys power | grep mWakefulness=
adb -s 3f6cc09b shell dumpsys window | grep -o 'isStatusBarKeyguard=[a-z]*'
```

长录屏在同一条设备 shell 里开头先发一次 WAKEUP（见 §3 模板）。

```bash
cd echo
flutter build apk --debug
adb -s 3f6cc09b install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 3f6cc09b shell am force-stop com.everse.echo
adb -s 3f6cc09b shell am start -n com.everse.echo/.MainActivity
sleep 4   # 等冷启动
```

## 3. 录屏（设备端单条 shell 模式）

screenrecord 与多次 input 事件必须写进**同一条** `adb shell '...'`
（后台 `screenrecord &` + sleep + swipe + `wait`），分多条命令会丢时序。
该 shell 内开头先放 `input keyevent KEYCODE_WAKEUP`，避免首段黑屏（§2）。
横滑翻页手势：

- 前进（左滑下一页）：`input swipe 900 2070 500 2070 1200`
  （4 页增益校准：拖 400px 严格翻一页；旧值拖到 250 共 650px 松手时
  惯性会越过一页，02→04 跳过笔记。后退 390px 不受影响）
- 后退（右滑）：**起手 x 必须 ≥600**，如 `input swipe 620 2070 1010 2070 1200`；
  从 x=250 起手会丢手势（导航条热区物理 x 531~1051、y≈2074）
- 两次滑动间隔 sleep 3~3.3s（含 1.2s 手势 + 落位后 650ms 唤醒保持）
- bit-rate 8000000、`--time-limit` ≤21s（直发飞书的安全上限）

正式录之前必须脱机验证每次点击：`input tap` 后 0.4s 截图确认 SnackBar/
按钮态变化，不能只看抽帧估算的坐标（终端页背景网格线极易被误判成按钮
描边，曾因此三个按钮全部点空）。当前按钮热区（1080×2160）：正常态
Wrap 两行，第一行 y≈1208（新消息 x≈383、异常 x≈749），第二行
y≈1373；异常态第三按钮缩短为「处理异常」后三按钮排成一行 y≈1290，
处理异常 x≈905。

录完 pull 到 `artifacts/lark-upload/`（已 gitignore）；设备串行操作持
`artifacts/.device.lock`，用完删 `/sdcard/*.mp4`。

## 4. ffmpeg 抽帧自检（agent 看不了视频，这是唯一自检手段）

接触印样总览（先看这张定位事件时刻）：

```bash
ffmpeg -y -loglevel error -i in.mp4 -vf "fps=2,scale=200:-1,tile=6x7" out.png
```

tile 行数必须给足：行数 ≥ ceil(时长×fps/列数)，否则报
"Cannot write more than one file with same name"。转场帧不可用，
落位帧时刻从印样反推（每次滑动后约 0.8s 落位）。

局部高帧率细看动画（页名牌区域在屏幕左下，y≈1600 起；转鼓在右下）：

```bash
ffmpeg -y -loglevel error -ss 1.05 -t 0.9 -i in.mp4 \
  -vf "fps=10,crop=620:460:0:1600,scale=465:-1,tile=9x1" out.png
```

抽单帧：`-ss T -frames:v 1`。截图直接 `adb exec-out screencap -p > f.png`。

## 5. 交付前裁剪与封面

发飞书的视频去掉尾部无效段并重编码（暗场高压缩，体积约 1MB/s 内正常）：

```bash
ffmpeg -y -loglevel error -i in.mp4 -t 16.5 \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
  -movflags +faststart send.mp4
ffmpeg -y -loglevel error -ss 2.5 -i in.mp4 -frames:v 1 cover.png
```

封面选**页名牌与转鼓同框**的稳态或故障高潮帧，不要选纯转场帧。
拼图/印样只用于自检，不随飞书消息发出。

## 6. 判定清单（以本次页名牌故障为例的通用标准）

- 触发条件类需求：在印样上逐次数唤醒/静默窗口，确认每个窗口行为与规则一致；
  边界场景（首/末页继续滑、快速连滑）必须单独验证
- 视觉终态：放大抽单帧确认无残留（色差副本/位移/透明片在动画末段归零）
- 同步类需求（如页名牌↔转鼓）：同框帧确认同帧出现/消失、底边对齐
- 自检通过后再装机之外不做声明；汇报措辞与证据一致
