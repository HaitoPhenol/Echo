# 思源 .sy 格式对照表（3.8.6 金标准）

> 本文件是 Echo 日记模块导出 `.sy.zip` 的格式唯一基准。
> 所有结论来自两份真实导出样本的逆向（2026-10-10，思源版本 **3.8.6**）：
>
> | 样本 | 内容 | 用途 |
> |---|---|---|
> | 文档级导出 | 单篇日记，含全部常用块类型（93 个带 ID 节点） | 节点/属性/行内标记全量枚举 |
> | 笔记本级导出 | 笔记本「示例笔记本」+ 年/月/日三级文档 | 目录树、conf.json、sort.json、zip 编码 |
>
> 规则：生成器输出与本文件冲突时以本文件为准；思源升级后必须重跑验证回路
> （见《[flutter-tech-plan.md](flutter-tech-plan.md)》测试章），并更新本文件。
> 上游需求文档：智谱清言《日记模块开发计划文档 v1.0》（已按实测修正其第 4 章）。

---

## 1. 物理与编码规则

- `.sy` 文件是**单行紧凑 JSON**（Go `json.Marshal` 风格，无多余空格、无缩进、UTF-8 无 BOM）。
- `.sy.zip`：
  - 只有**文件条目**，不含目录条目；路径分隔符 `/`；
  - 文件名含非 ASCII 时必须置 **UTF-8 通用位标志（general purpose bit 11 = 0x0800）**，
    否则 Windows 端思源导入会乱码；
  - 实测条目顺序：`.siyuan/conf.json`、`.siyuan/sort.json`、然后文档文件。
- 顶层文件夹名 = **笔记本显示名**（实测中文「示例笔记本」），**不是 22 位 ID**。
  笔记本 ID 由思源导入时分配，包内不出现。

## 2. 块 ID 规范

```
格式：YYYYMMDDHHMMSS-XXXXXXX
      └ 14 位秒级时间戳 ┘ └ 7 位 [a-z0-9] 随机串 ┘
```

- 93 个实测 ID 全部符合；同秒批量生成的节点共享时间戳前缀，随机段区分；
- 每个块节点的 `ID` 与其 `Properties.id` 严格相等；
- 文档根 ID === 文件名去掉 `.sy`；
- **ID 与 `updated` 解耦**：样本经"复制到另一笔记本"后全部块获得新 ID，
  但 `updated` 保留内容原始编辑时间（出现 updated 早于 ID 时间戳）。
  生成器对二者独立维护。
- 校验正则：`^\d{14}-[a-z0-9]{7}$`。

## 3. 笔记本包结构

实测树（笔记本级导出）：

```
示例笔记本/                                   ← 笔记本名
├── .siyuan/
│   ├── conf.json                             ← 笔记本配置
│   └── sort.json                             ← 文档手动排序
├── 20261010000159-mkzx9og.sy                 ← 年文档「2026」
└── 20261010000159-mkzx9og/                   ← 与父文档 ID 同名的文件夹
    ├── 20261010000213-y3naqzj.sy             ← 月文档「10 月」
    └── 20261010000213-y3naqzj/
        └── 20261010000332-jtbos5h.sy         ← 日文档「9日 周五」
```

层级规则（递归）：**子文档物理存放于"与父文档 ID 同名"的文件夹内，
文件名等于自身根 ID。** Echo 采用 **年 → 月 → 日 三级**（同实测）。

### 3.1 `.siyuan/conf.json`

实测全字段（14 个，紧凑 JSON，键序如下）：

```json
{"name":"示例笔记本","sort":0,"icon":"","closed":true,
 "refCreateSaveBox":"","refCreateSavePath":"",
 "docCreateSaveBox":"","docCreateSavePath":"","docCreateTemplatePath":"",
 "dailyNoteSavePath":"/daily note/{{now | date \"2006/01\"}}/{{now | date \"2006-01-02\"}}",
 "dailyNoteTemplatePath":"","sortMode":15,"encrypted":false,"boxCrypt":null}
```

Echo 导出包取值：`name`=导出时指定的笔记本名；`closed=true`；
三个保存路径及模板路径置空；`sort=0`、`sortMode=15`、`encrypted=false`、
`boxCrypt=null` 照实测。

### 3.2 `.siyuan/sort.json`

```json
{"20261010000159-mkzx9og":1,"20261010000213-y3naqzj":1,"20261010000332-jtbos5h":1}
```

包内**全部文档**（含年/月容器）的 ID 各映射 `1`。上游需求文档遗漏此文件，
Echo 生成器必须输出。

## 4. .sy 文档通用结构

### 4.1 文档根节点

```json
{"ID":"20261009233451-u7ay0k0","Spec":"2","Type":"NodeDocument",
 "Properties":{
   "custom-dailynote-20261009":"20261009",
   "id":"20261009233451-u7ay0k0",
   "title":"9日 周五","type":"doc","updated":"20261009235303"},
 "Children":[ ... ]}
```

- 顶层字段固定顺序：`ID, Spec, Type, Properties, Children`；
- `Spec` 实测恒为字符串 `"2"`；
- `Properties` 是 JSON 对象，**键按字典序排列**（Go map 序列化特征），
  实测序：`custom-* < id < title < type < updated`。生成器必须排序输出，
  保证往返 diff 干净；
- 文档级 `custom-*` 任意键值均被完整保留（实测的日记插件属性
  `custom-dailynote-YYYYMMDD` 即此机制），值一律为字符串；
- 空容器文档允许省略 `Children` 键。

### 4.2 属性键约定

| 键 | 出现位置 | 说明 |
|---|---|---|
| `id` | 全部节点 | 与 `ID` 相同 |
| `updated` | 全部节点 | 14 位秒级时间戳字符串，内容变更才刷新 |
| `title` / `type` | 文档根 | `type` 恒为 `"doc"` |
| `style` | 块 | 自由 CSS 声明串，思源原样存储不校验 |
| `custom-*` | 文档根（Echo 用法） | 天气/心情/睡眠等结构化数据通道 |
| 其它 | 超级块等 | 如 `ligatures`、表格 `colgroup`（本项目不生成） |

含 `style` 的块，Properties 键序为 `id < style < updated`。

## 5. Echo 支持的块子集（生成范围）

### 5.1 段落 NodeParagraph

有文本：

```json
{"ID":"20261009233657-36xq8l5","Type":"NodeParagraph",
 "Properties":{"id":"20261009233657-36xq8l5","updated":"20261009233700"},
 "Children":[{"Type":"NodeText","Data":"正文。"}]}
```

空块：无 `Children` 键。行内换行：`Data` 中直接是真实 `\n` 字符。

### 5.2 标题 NodeHeading

```json
{"ID":"20261009233616-34rvgn0","Type":"NodeHeading","HeadingLevel":2,
 "Properties":{"id":"20261009233616-34rvgn0","updated":"20261009235303"},
 "Children":[{"Type":"NodeText","Data":"二级"}]}
```

实测 H1–H6 全部存在；Echo 生成 H1–H3，解析容忍 H1–H6。

### 5.3 块底色（重要修正）

上游需求文档写的是固定 hex（`background-color: #fff3bf;`），**实测调色板
写入的是思源主题 CSS 变量**，canonical 形态：

```json
"style":"background-color: var(--b3-font-background12); --b3-parent-background: var(--b3-font-background12);"
```

- 色号 `--b3-font-background1` … `--b3-font-background13`；
- **必须同时写 `--b3-parent-background`**（供嵌套子块继承）；
- 用变量而非 hex 的收益：导入后随思源深/浅色主题自动反色；
- Echo 调色板按色号映射（编辑期显示的 RGB 从思源主题 CSS 取色，
  见技术方案 M3），导出期写变量名。

> 注意：实测部分从浏览器版复制的块 style 中混入了 DarkReader 扩展注入的
> `--darkreader-*` 声明。思源照单全收（style 不校验），但 Echo **不得生成**
> 这些垃圾声明。

## 6. 子集外节点（解析时降级，不生成）

实测样本中出现、Echo 回读时按"纯文本占位块"处理的类型：

| 类型 | 实测要点 |
|---|---|
| `NodeTextMark` | 行内样式。类型枚举实测：`strong`/`em`/`u`/`s`/`mark`/`code`/`kbd`/`sup`/`sub`/`inline-math`/`inline-memo`/`a`（链接，带 `TextMarkAHref`/`TextMarkATitle`）/`text`（带 span IAL 的自定义样式） |
| `NodeKramdownSpanIAL` | 行内 `{: style="..."}`，与 `TextMarkType:"text"` 配对出现 |
| `NodeList` / `NodeListItem` | `ListData.Typ`：0 无序（默认省略）、1 有序、3 任务；无序 `BulletChar=42`，`Marker` 为 base64（`Kg==`→`*`）；有序带 `Delimiter=46` 与 `Num` |
| `NodeTaskListItemMarker` | `TaskListItemMarker`：32 空格=未完成，88（X）=完成（`TaskListItemChecked:true`） |
| `NodeBlockquote`(+`Marker`) | 引述，子级可嵌段落/列表 |
| `NodeCodeBlock` | `IsFencedCodeBlock` + 四个 fence/code 子节点；语言字段 `CodeBlockInfo` 为 base64（`Yw==`→`c`） |
| `NodeThematicBreak` | 分割线 `---` |
| `NodeTable`/`Head`/`Row`/`Cell` | `TableAligns`、`Properties.colgroup` |
| `NodeHTMLBlock` | 原始 HTML 存 `Data` |
| `NodeSuperBlock`(+open/close/`LayoutMarker`) | 超级块，布局 `col`/`row`；子块 style 带 width/flex |
| `NodeCallout` | `CalloutType`：TIP/NOTE/IMPORTANT/WARNING/CAUTION，含 `CalloutIcon`/`CalloutTitle` |
| 卡片色段落 | `style` 用 `--b3-card-{info|success|warning|error}-{color|background}` |
| `NodeBackslash` | 转义标记（如 `~`） |

降级原则：只取节点内文本（`NodeText.Data` 与 `NodeTextMark.TextMarkTextContent`
顺序拼接），UI 标注"此内容请在思源中查看"。

## 7. 验证回路（每个里程碑必跑）

1. Echo 生成 `.sy.zip`；
2. 思源 **3.8.6**（锁定版本）笔记本右键 → 导入 → SiYuan .sy.zip；
3. 检查清单：
   - [ ] 文档树为 笔记本 / 年 / 月 / 日 四级路径；
   - [ ] 标题级别、段落文本、行内换行正确；
   - [ ] 块底色与调色板色号一致（深色主题下正确反色）；
   - [ ] 文档属性面板出现全部 `custom-*`；
   - [ ] 属性视图可按 `custom-mood` 等字段聚合成图；
   - [ ] 重复导入同一容器 ID 不产生重复年/月文档（增量幂等）；
4. 在思源中改动后导出，结构变化回填本对照表；
5. 任一失败 → 修生成器/对照表 → 里程碑不通过。

## 8. 已归档的上游文档偏差

| # | 上游《开发计划 v1.0》预研 | 3.8.6 实测 | 处置 |
|---|---|---|---|
| 1 | 包顶层文件夹用 22 位 ID | 用笔记本显示名 | 生成器参数化笔记本名 |
| 2 | 只有 conf.json | 还有必带的 sort.json | 补生成 |
| 3 | 年→日两级 | 年→月→日三级 | 生成器按三级 |
| 4 | 底色写 hex `#fff3bf` | 写 `var(--b3-font-backgroundN)` + parent | 按 canonical 串 |
| 5 | `Spec` 预研 "2" | ✓ 证实 | — |
| 6 | 22 位 ID、custom-* 保留 | ✓ 证实 | — |
| 7 | 年文档 ID 当年 1 月 2 日 | 样本为任意时间戳 | Echo 改用确定性容器 ID（见技术方案） |
