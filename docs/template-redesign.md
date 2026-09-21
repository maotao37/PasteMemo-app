# 模板功能优化设计

> 状态：待评审 · 2026-09-21 · 基于 develop 分支现状调查

## 一、现状与核心问题

模板功能由提交 `a41aad4` 引入后无独立迭代。当前只有两个入口：

- **设置 → 模板库**（`Sources/Views/Settings/TemplateLibraryView.swift`）：列表 + 编辑器，唯一的管理界面
- **主窗口工具栏菜单**（`MainWindowView.swift:250-257`）：点击模板 = 渲染后**仅复制到剪贴板** + toast

核心问题（按影响排序）：

1. **不能粘贴回原应用** —— 剪贴板条目在快捷面板回车即粘贴回目标应用（`QuickPanelWindowController.dismissAndPaste` + CGEvent ⌘V），模板却要手动 ⌘V，体验割裂
2. **快捷面板零集成** —— `isQuickAccess` 唯一作用是主窗口工具栏菜单；快捷面板、状态栏、命令面板均无入口
3. **编辑器体验粗糙** —— 变量芯片只能**追加到内容末尾**（不能插到光标处）；`icon` 字段有模型无 UI，永远是默认图标；无搜索；删除无确认；无"复制模板"
4. **变量系统太弱** —— 仅 6 个固定变量，日期格式写死（medium/short），无自定义填空变量
5. **没有内容来源** —— 无法从剪贴板历史"存为模板"，只能在设置页手打

## 二、设计原则

- 模板定位为**输入加速器**，融入快捷面板主流程，而不是设置页里的独立资料库
- 复用既有交互语言：页签、⌘N 键帽、页脚提示、粘贴回写管线，不发明新范式
- 渐进式披露：默认点开即用；进阶能力（格式参数、填空变量）按需使用
- 纯文本范围内做到极致；富文本/图片模板、按模板全局热键另立项目

## 三、方案总览

| 问题 | 方案 | 改动面 |
|---|---|---|
| 不能粘贴回去 | 快捷面板新增「模板」页签，Enter 直接粘贴回目标应用 | 中 |
| 变量系统弱 | 格式参数 `{{date:yyyy-MM-dd}}` + 自定义填空变量 `{{客户名}}` | 小 |
| 编辑器粗糙 | 管理界面重设计：图标选择、光标处插变量、搜索、复制模板、删除确认、变量高亮 | 中 |
| 没有内容来源 | 剪贴板历史右键「存为模板」（轻量 sheet） | 小 |
| 入口少 | 状态栏「模板」子菜单 + 主窗口菜单增强（摘要行 + 管理入口） | 小 |

## 四、详细设计

### 4.1 变量与渲染系统（`Sources/Engine/TemplateRenderer.swift`）

语法：`{{变量}}` 或 `{{变量:格式参数}}`，正则 `\{\{([^:}]+)(?::([^}]*))?\}\}`。

**内置变量**（保留原 6 个，UI 按组展示）：

| 组 | 变量 | 格式参数 |
|---|---|---|
| 日期时间 | `date` `time` `datetime` | 支持 ICU 日期格式，如 `{{date:yyyy-MM-dd}}`、`{{time:HH:mm}}`；非法格式回退默认样式并 console 警告 |
| 个人 | `name` `project` | 忽略参数 |
| 剪贴板 | `clipboard` | 忽略参数（面板打开时刻的剪贴板快照，见 4.3） |

**自定义填空变量**：非内置名的 `{{任意词}}` 视为填空变量。

- `placeholderNames(in:)` 提取（按出现顺序去重），供 UI 生成输入框
- 渲染时用填写值替换；未填写渲染为空串
- ⚠ **行为变更**：现状未知变量原样保留，改为"填写值或空串"（标准 snippet 语义；需同步更新 `TemplateRendererTests`，升级说明提一句）

**新 API**：

```swift
enum TemplateRenderer {
    static let builtinVariables: [String]           // 供 UI 分组展示
    static func render(_ template: String, context: TemplateContext,
                       fills: [String: String] = [:], locale: Locale = .current) -> String
    static func placeholderNames(in template: String) -> [String]
}
```

### 4.2 管理界面重设计（`TemplateLibraryView.swift`）

布局保持 `NavigationSplitView`，对齐 `AutomationManagerView` 的成熟范式。

**侧栏**：

- 顶部搜索框：过滤 名称 + 内容，实时
- 行：图标 + 名称 + 内容首行摘要（灰色单行截断）——信息密度对齐 `ClipRow`
- 右键菜单：复制渲染文本 / 复制模板（duplicate）/ 删除…
- 底部工具条：＋ － ⧉（复制模板）＋ 模板计数
- 拖拽排序保留（`onMove` 重写 sortOrder）

**编辑器**（从上到下五区）：

```
┌─────────────────┬──────────────────────────────────────────────┐
│ 🔍 搜索模板      │ [▣] 模板名称____________        快捷入口 [◉]  │
│─────────────────│                                              │
│ ▣ 晨会问候       │ ▹ 个人资料（姓名 / 项目）             ▾       │
│   王小明，早上好  │                                              │
│ ▣ 周报模板       │ 模板内容                                      │
│   本周完成…      │ ┌──────────────────────────────────────────┐ │
│ ▣ 客户回复       │ │ {{name}}，你好：                          │ │
│   (拖拽排序)     │ │ {{clipboard}}         （{{ }} 高亮显示）   │ │
│                 │ └──────────────────────────────────────────┘ │
│                 │ 时间  [{{date}} ▾] [{{time}}] [{{datetime}}]  │
│                 │ 个人  [{{name}}]  [{{project}}]               │
│                 │ 其他  [{{clipboard}}]                         │
│                 │ 预览                               42 字 · 3 行│
│                 │ ┌──────────────────────────────────────────┐ │
│                 │ │ 王小明，你好：   （填空变量→内联输入框）    │ │
│                 │ └──────────────────────────────────────────┘ │
│ ＋  －  ⧉  共 5 个│                             [复制渲染文本 ⌘↩]│
└─────────────────┴──────────────────────────────────────────────┘
```

1. **基本信息**：图标选择器（popover：SF Symbols 网格，精选约 40 个 + 搜索）；名称；快捷入口开关
2. **个人资料**收进 `DisclosureGroup`（默认收起）——这是全局设置，不该占模板编辑的黄金位置
3. **内容编辑**：等宽 TextEditor，`{{变量}}` 用 accent 色高亮（overlay 自绘或 NSAttributedString）；变量芯片按组排列，点击**插入光标处**（修复追加到末尾的问题，经 NSTextView selection 实现）；`{{date}}` 芯片带格式预设 ▾（`2026-09-21` / `09/21/2026` / `2026年9月21日`）
4. **预览**：实时渲染；填空变量显示为内联小输入框，填写即时反映到预览；底部注记数据来源（date=今天、clipboard=当前剪贴板前 60 字）
5. **操作**：复制渲染文本 ⌘↩（保留现状）

**行为补齐**：删除弹确认 alert（标题含模板名）；新建后焦点落在名称框并全选；复制模板 = 同内容副本，名称加"副本"后缀，插到原模板之后。

### 4.3 快捷面板集成（核心新增，`Sources/Views/QuickPanel/`）

```
┌──────────────────────────────────────────────┐
│ 🔍 搜索名称或内容                              │
│ 置顶  全部  模板  文本  链接  图片  …  分组 ▾  │
│────────────────┬─────────────────────────────│
│ ▣ 晨会问候  ⌘1 │ （预览区：渲染后全文          │
│   王小明，早上好 │   + 变量来源注记）            │
│ ▣ 周报模板  ⌘2 │                             │
│────────────────┴─────────────────────────────│
│ ⏎ 粘贴到“Xcode”      ⌘↩ 仅复制               │
└──────────────────────────────────────────────┘

选中含填空变量的模板时，搜索栏下方出现填写条：
│ ┌ 填写变量 ─────────────────────────────────┐ │
│ │ 客户 [________]   事项 [________]   Tab→下一 │ │
│ └───────────────────────────────────────────┘ │
```

- **页签**：`QuickPanelTabItem`（`QuickPanelPositioning.swift:127`）新增 `.templates`，图标 `text.badge.plus`，文案复用 `settings.templates`；**有任何模板时显示**，id 加入 `defaultTabOrderIDs`（排在「全部」之后），确保隐藏/排序序列化正确（63f624d 修复的机制自动覆盖新 id）
- **显示范围**：快捷面板展示**全部**模板（靠搜索过滤），不看 `isQuickAccess`——该开关重新定义为只控制"菜单类入口"（主窗口工具栏菜单 + 状态栏子菜单，空间有限的场景）
- **筛选持久化**：`QuickFilter` 加 `.templates` case + `storageString`，随 `lastFilterKey` 恢复
- **行 UI**：模板图标（类型色底 + 描边，同 `ClipRow` 缩略图风格）+ 名称 + 渲染后首行摘要（灰色）+ ⌘N 键帽（复用 `QuickClipRow` 角标样式）
- **键盘**：Enter = 渲染 → `dismissAndPaste` 粘贴回目标应用（`quickPanelAutoPaste = false` 时降级为复制，复用现有分支）；⌘Enter = 仅复制；⌘1-9、↑↓ 导航复用面板级 key monitor
- **搜索**：匹配 名称 + 内容
- **剪贴板快照**：面板 `show()` 时快照 `NSPasteboard.general`，渲染预览与最终粘贴用同一份值，避免面板悬停期间剪贴板变化导致所见非所得
- **填写条**：选中行含填空变量时出现；每个变量一个紧凑输入框，Tab 在框间循环，Enter 粘贴；无填写时该变量按空串渲染
- **lastUsedAt**：每次粘贴/复制成功后更新（供状态栏"最近使用"排序）

**实现要点**（工作量主要在此）：

- 列表区现状是 `NativeClipHistoryList`（与 `ClipItemStore` 强耦合）。模板页签需要并列的 `TemplateListView`（普通 SwiftUI List，行高对齐 48pt），通过"当前页签的可见条目提供者"把选中项/条目数接入现有 key monitor（`installKeyMonitor` 里 ↑↓/Enter/⌘N 都走 `visibleItems` 类抽象）
- 粘贴路径完全复用 `QuickPanelWindowController.dismissAndPaste` + `TemplateActions.renderedText`，无需新写事件合成

### 4.4 其他入口

- **剪贴板历史「存为模板」**：快捷面板行右键菜单 + 主窗口右键菜单新增「存为模板」→ 轻量 sheet：名称（预填首行截断，可改）+ 内容（可继续插变量）+ 保存；空内容禁用保存。形成"历史 → 模板"的内容闭环
- **状态栏菜单**（`StatusBarController.buildMenu`，纯命令式易插入）：「接力模式」之后加「模板」子菜单，列 `isQuickAccess` 模板（按 lastUsedAt 排序，前 15 个，带图标），点击 = 渲染复制 + toast；底部「管理模板…」跳设置
- **主窗口工具栏菜单**：条目加图标与渲染首行摘要（menu item subtitle 风格）；底部加「管理模板…」；点击行为**保持复制**（主窗口是管理场景，焦点不在目标应用，粘贴回去语义歧义）

## 五、数据模型与兼容性

```swift
// TemplateSnippet 新增（有默认值 → SwiftData 轻量迁移，无需手工迁移代码）
var lastUsedAt: Date = .distantPast
```

- 其余字段不变；`ExportTemplate` 导出结构加**可选** `lastUsedAt`，旧备份文件导入不受影响（`DataPorter` 按 templateID 去重逻辑不动）
- 备份引擎（WebDAV/本地）自动兼容

## 六、本地化新增 key（11 种语言）

```
template.searchPlaceholder     搜索模板
template.duplicate              复制模板
template.duplicate.suffix       副本
template.deleteConfirm          删除“%@”？此操作无法撤销。
template.icon                   图标
template.variables.datetime     日期时间
template.variables.personal     个人
template.variables.clipboard    剪贴板
template.preview.source         渲染自：date=今天 · clipboard=当前剪贴板
template.fill.title             填写变量
template.fill.hint              Tab 切换 · Return 粘贴
action.saveAsTemplate           存为模板
saveAsTemplate.save             保存模板
```

## 七、分期实施

| 期 | 内容 | 规模 |
|---|---|---|
| 一（界面优化） | 渲染器升级（格式参数 + 填空 + 单测）；管理界面重设计（搜索 / 图标选择 / 光标处插入 / 复制模板 / 删除确认 / 变量高亮 / 预览内填空） | 中 |
| 二（功能完善） | 快捷面板模板页签（含填写条 + 粘贴回写 + 搜索 + lastUsedAt）；「存为模板」右键 + sheet；状态栏子菜单；主窗口菜单增强 | 大 |
| 三（可选增强） | `{{selection}}` 变量（需辅助功能 API 读选中文本）；命令面板 / MCP 模板工具；README 文档 | — |

## 八、决策点（默认按推荐执行，可否决）

1. **未知变量语义变更**：原样保留 → 填写值或空串。推荐：标准 snippet 语义；旧模板若含字面 `{{x}}` 文本会开始被清空，概率极低，升级说明提及
2. **快捷面板显示全部模板**而非仅 `isQuickAccess`。推荐：面板有搜索，无需二次筛选；`isQuickAccess` 专注菜单类入口
3. **Enter 默认粘贴回原应用**（而非复制）。推荐：与剪贴板条目行为一致，受 `quickPanelAutoPaste` 设置约束
4. **主窗口工具栏菜单保持复制**不改为粘贴。推荐：管理场景焦点不在目标应用
