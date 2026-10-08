#!/usr/bin/env python3
"""夜间真机冒烟：装指定 APK → 按 usage-guide 几何执行手势序列 →
逐屏截图 + 全程录屏 → 写报告 index.md 并追加台账 LEDGER.md。

设备操作全程持有 artifacts/.device.lock 文件锁（flock），
多个 agent 并发时自动串行，禁止绕过本脚本直接 adb install。

用法：
  smoke.py --label <标签> --apk <apk 路径> [--branch <名>] [--sha <hash>]
"""
import argparse
import datetime
import fcntl
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ART = REPO / "artifacts"
APKS = ART / "apks"
REPORTS = ART / "reports"
LOCK = ART / ".device.lock"
LEDGER = ART / "LEDGER.md"
PKG = "com.everse.echo"


def adb(args, timeout=120, check=True):
    return subprocess.run(
        ["adb", *args], capture_output=True, timeout=timeout, check=check
    )


def text(args, timeout=120):
    return adb(args, timeout=timeout).stdout.decode(errors="replace")


def now_stamp():
    return datetime.datetime.now().strftime("%Y%m%d-%H%M%S")


def metrics():
    """返回 (物理w, 物理h, 密度比, 逻辑w, 逻辑h, 底部安全区sb逻辑值)。"""
    size = text(["shell", "wm", "size"])
    m = re.search(r"(\d+)\s*x\s*(\d+)", size)
    if not m:
        sys.exit("无法解析 wm size：%r" % size)
    pw, ph = int(m.group(1)), int(m.group(2))

    dens = text(["shell", "wm", "density"])
    m = re.search(r"(\d+)", dens.splitlines()[-1])
    if not m:
        sys.exit("无法解析 wm density：%r" % dens)
    scale = int(m.group(1)) / 160.0
    lw, lh = pw / scale, ph / scale

    # 底部安全区：尝试从 WindowManager 的 stable inset 取，取不到退回经验值。
    # 19dp 为小米 MIX 2S（density 440）实测，见 engineering_standards 1.15
    # 取证坐标反推（物理 y=2050 / 2.75 = 逻辑 745.5 = h−sb−21）；换设备重核。
    sb = 19.0
    dump = text(["shell", "dumpsys", "window"], timeout=60)
    m = re.search(r"mStableInsets[^\n]*?bottom=(\d+)", dump)
    if m and int(m.group(1)) > 0:
        sb = int(m.group(1)) / scale
    return pw, ph, scale, lw, lh, sb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--apk", required=True)
    ap.add_argument("--branch", default="")
    ap.add_argument("--sha", default="")
    args = ap.parse_args()

    label = re.sub(r"[^A-Za-z0-9_.-]+", "-", args.label).strip("-") or "run"
    apk = Path(args.apk).resolve()
    if not apk.is_file():
        sys.exit("APK 不存在：%s" % apk)

    ART.mkdir(exist_ok=True)
    APKS.mkdir(exist_ok=True)
    REPORTS.mkdir(exist_ok=True)

    lock_fd = os.open(str(LOCK), os.O_RDWR | os.O_CREAT, 0o644)
    print("等待设备锁 ...", flush=True)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    print("已持有设备锁", flush=True)

    stamp = now_stamp()
    report = REPORTS / f"{stamp}-{label}"
    report.mkdir()
    shots = report / "shots"
    shots.mkdir()

    try:
        run(label, apk, report, shots, stamp, args.branch, args.sha)
    except Exception as exc:  # 失败也要留下台账记录
        ledger_row(stamp, label, args.branch, args.sha,
                   apk.name if apk else "-", report.name, "失败：%s" % exc)
        raise


def run(label, apk, report, shots, stamp, branch, sha):
    adb(["wait-for-device"])
    pw, ph, scale, w, h, sb = metrics()
    print("设备 %dx%d density比%.3f 逻辑 %.1fx%.1f sb=%.1f" % (pw, ph, scale, w, h, sb),
          flush=True)

    def px(x, y):
        return round(x * scale), round(y * scale)

    def tap(name, lx, ly, hold_ms=0):
        x, y = px(lx, ly)
        if hold_ms:
            adb(["shell", "input", "swipe", str(x), str(y), str(x), str(y),
                 str(hold_ms)])
        else:
            adb(["shell", "input", "tap", str(x), str(y)])

    def swipe(lx1, ly1, lx2, ly2, dur_ms):
        x1, y1 = px(lx1, ly1)
        x2, y2 = px(lx2, ly2)
        adb(["shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2),
             str(dur_ms)])

    def back():
        adb(["shell", "input", "keyevent", "4"])

    # —— 几何（与 docs/usage-guide.md 第 5 节同一组公式）——
    nav_l = w - 14 - w / 2
    dot_l = nav_l + 5
    dot_r = w - 19
    bar_l = nav_l + 15
    bar_r = w - 29
    bar_cx = (bar_l + bar_r) / 2
    bar_cy = h - sb - 21
    handle_x = 14 + 0.06 * w
    ai_l = 28 + 0.12 * w
    ai_cx = ai_l + (0.38 * w - 56) / 2
    dock_x = min(0.78 * w, 340) + 14

    def shot(fname):
        png = adb(["exec-out", "screencap", "-p"]).stdout
        (shots / (fname + ".png")).write_bytes(png)
        time.sleep(0.15)

    steps = []

    def step(fname, desc, fn):
        steps.append((fname, desc))
        print("· %s %s" % (fname, desc), flush=True)
        fn()
        shot(fname)

    # 装包（-d 允许同/低 versionCode 覆盖）
    print("安装 %s" % apk.name, flush=True)
    adb(["install", "-r", "-d", str(apk)], timeout=300)

    remote_vid = "/sdcard/nightly_run.mp4"
    adb(["shell", "rm", "-f", remote_vid], check=False)
    rec = subprocess.Popen(
        ["adb", "shell", "screenrecord", "--bit-rate", "8000000",
         "--time-limit", "120", remote_vid],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1.0)

    try:
        def cold_boot():
            adb(["shell", "input", "keyevent", "224"])
            adb(["shell", "am", "force-stop", PKG])
            time.sleep(0.6)
            adb(["shell", "monkey", "-p", PKG,
                 "-c", "android.intent.category.LAUNCHER", "1"], timeout=30)
            time.sleep(4.2)  # MIX 2S 冷启动到可交互约 4~4.5s（1.15 实测）
        step("01", "冷启动：强停后重新拉起（4.2s）", cold_boot)
        step("02", "点右圆点 → 聊天页", lambda: (tap("", dot_r, bar_cy),
                                                 time.sleep(1.2)))
        row_y = h * 0.45
        step("03", "会话行左滑 170 → 露出操作按钮", lambda: (
            swipe(0.82 * w, row_y, 0.82 * w - 170, row_y, 260),
            time.sleep(0.5)))
        step("04", "右拖回 → 操作区复位", lambda: (
            swipe(0.82 * w - 170, row_y, 0.82 * w, row_y, 220),
            time.sleep(0.4)))
        step("05", "点左圆点 → 回控制台", lambda: (tap("", dot_l, bar_cy),
                                                   time.sleep(1.2)))
        step("06", "长按导航条 550ms → 搜索胶囊", lambda: (
            tap("", bar_cx, bar_cy, 550), time.sleep(1.3)))
        step("07", "点胶囊外部 → 关闭搜索", lambda: (
            tap("", w / 2, 120), time.sleep(0.6)))
        step("08", "点把手 → 本页操作竖单", lambda: (
            tap("", handle_x, bar_cy), time.sleep(0.7)))
        step("09", "返回键 → 关闭竖单", lambda: (back(), time.sleep(0.5)))
        step("10", "右拖把手到停靠位 → 侧边抽屉", lambda: (
            swipe(handle_x, bar_cy, dock_x, bar_cy, 360), time.sleep(0.8)))
        step("11", "返回键 → 关闭抽屉", lambda: (back(), time.sleep(0.4)))
        def arc_hold_shot():
            # 弧只在手指按住时存在，松手即收（或触发）。按 1.15 经验：
            # 发起 2.6s 长甩、在按住相位截图、终点故意停在全部热区之外。
            ax, ay = px(bar_l + (bar_r - bar_l) * 0.25, bar_cy)
            ex, ey = px(bar_l + (bar_r - bar_l) * 0.25, bar_cy - 230)
            held = subprocess.Popen(
                ["adb", "shell", "input", "swipe",
                 str(ax), str(ay), str(ex), str(ey), "2600"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(1.3)
            shot("12")  # 弧展开 + 最近按钮高亮（手指仍按住）
            held.wait(timeout=10)
            time.sleep(0.7)  # 终点在热区外 → 不触发，弧收起
        print("· 12 上甩 → 快捷操作弧（按住相位抓拍）", flush=True)
        steps.append(("12", "导航条 1/4 处上甩 230 → 快捷操作弧（按住相位抓拍，终点在热区外不触发）"))
        arc_hold_shot()
        step("13", "返回键 → 收起快捷弧", lambda: (back(), time.sleep(0.5)))
        step("14", "长按 AI 条 550ms → AI 对话框与键盘", lambda: (
            tap("", ai_cx, bar_cy, 550), time.sleep(1.4)))
        step("15", "返回键 → 关闭 AI 对话框", lambda: (back(), time.sleep(0.6)))

        def double_tap():
            tap("", bar_l + (bar_r - bar_l) * 0.55, bar_cy)
            time.sleep(0.12)
            tap("", bar_l + (bar_r - bar_l) * 0.9, bar_cy)
        step("16", "300ms 内双击导航条右侧 → 直达末页", lambda: (
            double_tap(), time.sleep(1.2)))

        def back_home():
            for _ in range(3):
                tap("", dot_l, bar_cy)
                time.sleep(0.55)
        step("17", "连点左圆点 3 次 → 回到控制台", lambda: (
            back_home(), time.sleep(0.8)))
    finally:
        time.sleep(0.8)
        rec.terminate()
        try:
            rec.wait(timeout=5)
        except subprocess.TimeoutExpired:
            rec.kill()
        # 通知录制进程落盘后再拉取
        adb(["shell", "pkill", "-INT", "screenrecord"], check=False)
        time.sleep(2.5)
        pull = adb(["pull", remote_vid, str(report / "video.mp4")],
                   timeout=120, check=False)
        if pull.returncode != 0:
            print("录屏拉取失败：", pull.stdout, pull.stderr, flush=True)
        adb(["shell", "rm", "-f", remote_vid], check=False)

    write_index(report, apk, label, stamp, branch, sha, steps,
                (pw, ph, scale, w, h, sb),
                (report / "video.mp4").is_file())
    ledger_row(stamp, label, branch, sha, apk.name, report.name, "OK")
    print("报告：%s" % report, flush=True)


def write_index(report, apk, label, stamp, branch, sha, steps, geo, has_vid):
    pw, ph, scale, w, h, sb = geo
    lines = [
        "# 冒烟报告 · %s" % label,
        "",
        "- 时间：%s" % stamp,
        "- 构建：`%s`" % apk.name,
        "- 来源：`%s@%s`" % (branch or "?", (sha or "?")[:8]),
        "- 设备：物理 %dx%d / density 比 %.3f / 逻辑 %.1f×%.1f / sb≈%.1f"
        % (pw, ph, scale, w, h, sb),
        "",
    ]
    if has_vid:
        lines += ["[▶ 全程录屏 video.mp4](video.mp4)", ""]
    lines += ["## 截图序列（顺序即脚本操作顺序）", ""]
    for fname, desc in steps:
        lines += [
            "### %s · %s" % (fname, desc),
            "",
            "![](shots/%s.png)" % fname,
            "",
        ]
    (report / "index.md").write_text("\n".join(lines), encoding="utf-8")


def ledger_row(stamp, label, branch, sha, apk_name, report_name, result):
    if not LEDGER.exists():
        LEDGER.write_text(
            "# 夜间台账（每行 = 一次出包冒烟，新行追加在表底）\n\n"
            "| 时间 | 标签 | 来源 | APK | 报告 | 结果 |\n"
            "|---|---|---|---|---|---|\n",
            encoding="utf-8")
    row = "| %s | %s | %s@%s | %s | [%s](reports/%s/index.md) | %s |\n" % (
        stamp, label, branch or "?", (sha or "?")[:8], apk_name,
        report_name, report_name, result)
    with open(LEDGER, "a", encoding="utf-8") as f:
        f.write(row)


if __name__ == "__main__":
    main()
