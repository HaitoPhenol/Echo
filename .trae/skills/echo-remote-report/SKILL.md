---
name: echo-remote-report
description: Echo 远程汇报流程——把真机截图与测试/出包报告通过飞书发到「Echo 夜间报告」群，大文件按需归档云盘。用户远程工作、夜间盲跑、人不在手机旁、只能用移动端 Trae（收不到图片）时使用；本地能直接对话时不用。
---

# Echo 远程汇报（飞书）

用户远程时只能用移动端 Trae 发文字、**接收不到图片**。真机效果因此走飞书：
截图/报告发到固定群；录屏/APK 等大文件**仅在用户有要求时**归档云盘并附链接，
不是每次必传。

**本技能只规范操作方式（发到哪、以什么身份、图片怎么进消息），不规范内容**：
汇报什么、写多长、配几张图，按当次任务自由组织；下面的模板只是参考，
不需要凑字段。唯一固定的内容约定是**署名**（见第 1 节），
因为多个 agent 可能共用用户本人身份发消息。

## 0. 固定事实（不要重新建群/建文件夹）

- 身份：**用户本人**，所有命令带 `--as user`（认证由连接器外部托管，
  不执行任何 auth login/logout/config）。
- 报告群「Echo 夜间报告」chat_id：
  `oc_948b4c5e29a7753a946d35ca8f966222`
- 回退目标（用户与自己的私聊）：`oc_f314dd80350c8ba45bcbd90680621896`
- 云盘「Echo」文件夹 folder_token：`Yz6bfJXmqlstNAdQaKScNblnn6c`
  （URL https://kcn6axyj3vqj.feishu.cn/drive/folder/Yz6bfJXmqlstNAdQaKScNblnn6c）
- 命令统一加环境变量抑制升级噪音：
  `export LARKSUITE_CLI_NO_UPDATE_NOTIFIER=1 LARKSUITE_CLI_NO_SKILLS_NOTIFIER=1`
- 真机：小米 MIX 2S，1080×2160 物理像素，density 440（2.75x）。
  设备命令与几何细节见 `docs/engineering_standards.md` 1.15 节。

群或文件夹失效（API 返回 not found/permission denied）时**停止重试**，
把情况报告用户，不要自行新建第二个同名群/文件夹。

## 1. 标准流程

1. **持设备锁截图**（与 `scripts/nightly` 共用 `artifacts/.device.lock`，
   避免与并行出包抢设备）：

   ```bash
   STAMP=$(date +%Y%m%d-%H%M%S)
   SHOT="artifacts/lark-upload/<名>-${STAMP}.png"
   mkdir -p artifacts/lark-upload
   ( flock 9; adb exec-out screencap -p > "$SHOT" ) 9>artifacts/.device.lock
   ```

   截图顶部若有 MIUI「指针位置」调试红条，先关闭再重截：
   `adb shell settings put system pointer_location 0`（show_touches 同理）。
   本地副本留在 artifacts/lark-upload/（已在 gitignore，不进 git）。

2. **图片换 img_key**（消息内图片不会自动上传，这一步必须做；
   文件路径用相对 cwd 的路径）：

   ```bash
   lark-cli im images create --as user \
     --data '{"image_type":"message"}' --file "$SHOT" --json
   ```

3. **发富文本 post 到报告群**：`--markdown`，图片以
   `![说明](img_v3_xxx)` 内嵌，云盘/台账用普通 markdown 链接。
   夜间自动汇报必须带 `--idempotency-key <唯一键>`（同键 1 小时不重发）。
   先 `--dry-run` 给用户确认三要素：**收件人、身份、内容**；
   用户已明确授权发送（如"试试发一下"）时可直接发，发完回报链接。

   **署名（唯一的硬性内容约定）**：所有 agent 都以用户本人身份发送，
   群里无法靠发送者区分来源，因此消息标题要带 agent 标识，如
   `## 🤖 [builder] Echo 冒烟报告 …`；幂等键同样带前缀，
   如 `builder-smoke-<时间戳>`，避免并行 agent 撞键。

4. **大文件（录屏 mp4、APK）按需上传，不是常规步骤**：只有用户明确要
   （"把录屏/安装包发上来"）时才用云盘技能
   `lark-cli drive +upload --as user --folder-token Yz6bfJXmqlstNAdQaKScNblnn6c`
   上传并在消息附返回的 url；普通截图汇报不触发此步。

5. **验证**：需要确认落地时用
   `lark-cli im +messages-mget --as user --message-ids <id>`
   核对 msg_type=post、图片 key 在内容中；最后给用户群消息 applink。

## 2. 失败回退

群发不出去（机器人/权限/群被解散等）时，**不改用 bot 身份**，
改发到用户与自己的私聊 `oc_f314dd80350c8ba45bcbd90680621896`，
并在汇报里说明发生了回退。rate limit / 临时网络错误可有限重试；
not found / permission denied / missing scope 直接停止并报告。

## 3. 冒烟报告参考格式（可自由取舍）

字段不要求凑齐——远程汇报的核心是让用户**看到真机画面 + 知道结果**，
按当次情况写，三五句话加图也完全可以。

```markdown
## 🤖 [<agent 署名>] Echo 冒烟报告 <时间戳>

- 分支/版本：<branch> v<x.y.z+nn>（<short sha>）
- 门禁：analyze <结果> / test <通过数>
- 装机冒烟：<异常摘要或"全部正常">

![<画面说明>](<img_key>)

<需要时才加：录屏/APK/台账云盘链接>
```

配图按信息量选，能说明问题即可（控制台、快捷弧展开、抽屉半程、异常帧
都是常用画面）；不必把完整故事板塞进消息，artifacts/reports/ 本地留档，
用户点名要看再传云盘。

## 4. 边界

- 只做汇报，不借飞书流程改代码、不替用户做产品决定。
- 云盘目录整理、权限变更、删消息/文件等高风险写操作必须另行确认。
- 把本流程接进 `scripts/nightly/smoke.py` 自动触发属于改代码，
  需用户明确派活；技能本身只描述手工/半自动执行方式。
