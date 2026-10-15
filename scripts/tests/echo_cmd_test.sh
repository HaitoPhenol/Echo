#!/usr/bin/env bash
#
# echo_cmd_test.sh —— echo-cmd 脚本级回归（无设备，以 fake adb 驱动）。
#
# 背景：G5 真机终审发现 echo-cmd 的自动轮询从未生效——json_query 对 JSON
# bool 走 `print(v)` 输出大写 `True`，而主流程按小写 `"true"` 比较，async
# 分支整体短路。Dart 测试覆盖不到 bash 脚本，故此处补**脚本级自动化**：
#
#   A. json_query 标量与点路径快照（bool/string/int/null/list/dict），
#      含「缺失路径非零退出」——钉死上述 bool 大小写缺陷；
#   B. async 自动轮询端到端：不带 --no-wait 应轮询至 done、打印**内层**
#      终态信封、退出码 0，且 stderr 出现轮询提示；
#   C. --no-wait 只取 running 信封、不轮询（工作站侧开关语义不变）。
#
# 运行：scripts/tests/echo_cmd_test.sh   （任意 cwd，退出码 0 即全过）
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ECHO_CMD="$HERE/../echo-cmd"

FAILED=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; FAILED=1; }
assert_eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1（期望 [$2] 实得 [$3]）"; fi
}

# ---- A. 库模式 source：取 json_query（主流程被 BASH_SOURCE 守卫短路）----
# shellcheck disable=SC1090
source "$ECHO_CMD"
set +e +u +o pipefail

assert_eq 'json_query bool true  → 小写 true'  "true" "$(json_query '{"async":true}' async)"
assert_eq 'json_query bool false → 小写 false' "false" "$(json_query '{"async":false}' async)"
assert_eq 'json_query string 标量'   "sys.ping" "$(json_query '{"cmd":"sys.ping"}' cmd)"
assert_eq 'json_query int 标量'      "12020" "$(json_query '{"ms":12020}' ms)"
assert_eq 'json_query null → 空串'   ""      "$(json_query '{"x":null}' x)"
assert_eq 'json_query 点路径 dict 快照' '{"ok": true}' \
  "$(json_query '{"result":{"envelope":{"ok":true}}}' result.envelope)"
assert_eq 'json_query 点路径 list 快照' '[1, 2]' \
  "$(json_query '{"events":[1,2]}' events)"
assert_eq 'json_query 点路径标量'    "done" "$(json_query '{"result":{"status":"done"}}' result.status)"
if json_query '{"a":1}' a.b.c >/dev/null 2>&1; then
  fail 'json_query 缺失路径应非零退出'
else
  pass 'json_query 缺失路径非零退出'
fi

# ---- B/C. 端到端：fake adb 回灌 am broadcast 输出样式 ------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE_ADB="$TMP/adb"

# fake adb 只认 echo-cmd 下发的那一次广播：按 --es cmd 分发 canned 信封。
# 输出格式对齐真实 `am broadcast`：`... data="<json>"`（内层引号不转义）。
cat > "$FAKE_ADB" <<'FAKE'
#!/usr/bin/env bash
# fake adb（仅测试用）：pidof 回假 pid；broadcast 按 cmd 回灌信封。
set -uo pipefail
joined="$*"
if [[ "$joined" == *pidof* ]]; then echo 12345; exit 0; fi
cmd="$(printf '%s' "$joined" | grep -oE -e "--es cmd '[^']*'" | head -1 | sed "s/--es cmd '//; s/'$//")"
emit() { printf 'Broadcast completed: result=0, data="%s"\n' "$1"; }
case "$cmd" in
  sys.ping) emit '{"ok":true,"cmd":"sys.ping","ms":1,"result":{"alive":true}}' ;;
  sys.delay)
    # E4 首包：async running，jobId 用于后续轮询。
    emit '{"ok":true,"cmd":"sys.delay","ms":11,"async":true,"jobId":"job-1","result":{"status":"running","jobId":"job-1"}}' ;;
  sys.job.get)
    # 首次 running、第二次 done（跨进程计数用文件）。
    n=0; [[ -f "${FAKE_STATE:-/nonexistent}" ]] && n="$(cat "$FAKE_STATE")"
    n=$((n + 1)); printf '%s' "$n" > "$FAKE_STATE"
    if [[ "$n" -eq 1 ]]; then
      emit '{"ok":true,"cmd":"sys.job.get","ms":2,"result":{"status":"running","jobId":"job-1","cmd":"sys.delay"}}'
    else
      emit '{"ok":true,"cmd":"sys.job.get","ms":3,"result":{"status":"done","jobId":"job-1","envelope":{"ok":true,"cmd":"sys.delay","ms":12020,"result":{"sleptMs":12000}}}}'
    fi ;;
  *) emit '{"ok":false,"cmd":"'"$cmd"'","ms":1,"error":{"code":"UNKNOWN_COMMAND","message":"unknown"}}' ;;
esac
FAKE
chmod +x "$FAKE_ADB"
export FAKE_STATE="$TMP/state"

# B. 不带 --no-wait：自动轮询至 done，打印内层信封，退出 0。
OUT="$(ADB="$FAKE_ADB" "$ECHO_CMD" sys.delay --ms 12000 2>"$TMP/err")"
CODE=$?
assert_eq 'B 退出码 0' "0" "$CODE"
if [[ "$OUT" == *'"sleptMs": 12000'* ]]; then
  pass 'B 打印内层终态信封'
else
  fail "B 打印内层终态信封（实得：$OUT）"
fi
if [[ "$(cat "$TMP/err")" == *"轮询终态"* ]]; then
  pass 'B stderr 有轮询提示'
else
  fail 'B stderr 有轮询提示'
fi

# C. --no-wait：立即取 running 信封，不轮询。
rm -f "$FAKE_STATE"
OUT2="$(ADB="$FAKE_ADB" "$ECHO_CMD" sys.delay --ms 12000 --no-wait 2>"$TMP/err2")"
CODE2=$?
assert_eq 'C 退出码 0' "0" "$CODE2"
if [[ "$OUT2" == *'"async":true'* && "$OUT2" != *sleptMs* ]]; then
  pass 'C 只取 running 信封'
else
  fail "C 只取 running 信封（实得：$OUT2）"
fi
if [[ "$(cat "$TMP/err2")" != *"轮询终态"* ]]; then
  pass 'C 未轮询'
else
  fail 'C 未轮询'
fi

# ---- 汇总 -------------------------------------------------------------
echo '---'
if [[ "$FAILED" -eq 0 ]]; then
  echo 'echo_cmd_test: 全部通过'
else
  echo 'echo_cmd_test: 存在失败' >&2
fi
exit "$FAILED"
