import AppKit
import SwiftUI

/// 模板页签的键盘协调器。QuickPanelView 的 key monitor 在模板模式下把按键
/// 转发到这里，由当前可见的 QuickTemplatePane 注册处理闭包；填写输入框持有
/// 焦点时 `textInputActive` 为 true，箭头与字母让位给输入框。
@MainActor
final class QuickTemplatePaneCoordinator: ObservableObject {
    var moveSelection: ((Int) -> Void)?
    var confirm: ((_ cmdOnly: Bool) -> Void)?
    var shortcutPaste: ((Int) -> Void)?
    /// Tab 在填写框之间循环；没有填写框或已在最后一格时返回 false，
    /// 让按键落回共享 switch（切换标签）。
    var advanceFillFocus: (() -> Bool)?
    var textInputActive = false
}

/// 快捷面板「模板」页签：全宽单列，行内直接展示渲染结果首行；
/// 选中含填空变量的模板时顶部出现填写条。回车粘贴回原应用（⌘回车仅复制）。
struct QuickTemplatePane: View {
    let templates: [TemplateSnippet]
    let searchText: Binding<String>
    let coordinator: QuickTemplatePaneCoordinator

    @EnvironmentObject private var clipboardManager: ClipboardManager
    @AppStorage("quickPanelAutoPaste") private var quickPanelAutoPaste = true
    @State private var selectedTemplateID: String?
    @State private var fillValues: [String: String] = [:]
    @State private var lastClickedID: String?
    @State private var lastClickTime = Date.distantPast
    @FocusState private var focusedFillField: String?

    private var query: String {
        searchText.wrappedValue.trimmingCharacters(in: .whitespaces)
    }

    private var filtered: [TemplateSnippet] {
        let trimmed = query
        guard !trimmed.isEmpty else { return templates }
        return templates.filter { matches(template: $0, query: trimmed) }
    }

    private func matches(template: TemplateSnippet, query: String) -> Bool {
        template.name.localizedCaseInsensitiveContains(query)
            || template.content.localizedCaseInsensitiveContains(query)
    }

    private var selectedTemplate: TemplateSnippet? {
        if let selectedTemplateID, let match = visibleTemplate(withID: selectedTemplateID) {
            return match
        }
        return filtered.first
    }

    /// 选中的模板还必须在当前过滤结果里可见，否则退回第一项
    private func visibleTemplate(withID id: String) -> TemplateSnippet? {
        for template in filtered where template.templateID == id {
            return template
        }
        return nil
    }

    private var placeholders: [String] {
        selectedTemplate.map { TemplateRenderer.placeholderNames(in: $0.content) } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if !placeholders.isEmpty { fillBar }
            if filtered.isEmpty {
                Spacer()
                ContentUnavailableView(L10n.tr("template.noMatch"), systemImage: "magnifyingglass")
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    templateScrollList(proxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedTemplateID == nil { selectedTemplateID = filtered.first?.templateID }
            registerKeyHandlers()
        }
        .onChange(of: templates.count) { _, _ in
            registerKeyHandlers()
            pruneSelection()
        }
        .onChange(of: selectedTemplateID) { _, _ in
            fillValues = [:]
            focusedFillField = nil
            coordinator.textInputActive = false
        }
        .onChange(of: query) { _, _ in
            pruneSelection()
        }
        .onChange(of: focusedFillField) { _, newValue in
            coordinator.textInputActive = newValue != nil
        }
    }

    /// 搜索词或模板集合变化后，把不再可见的选中项重置到第一项
    private func pruneSelection() {
        guard let currentID = selectedTemplateID else { return }
        if visibleTemplate(withID: currentID) == nil {
            selectedTemplateID = filtered.first?.templateID
        }
    }

    /// 单独抽出来：ScrollViewReader 闭包里内联这段 + onChange 会让类型检查器超时
    private func templateScrollList(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { template in
                    row(template)
                        .id(template.templateID)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 6)
        }
        .onChange(of: selectedTemplateID) { _, newID in
            scrollToSelection(newID, proxy: proxy)
        }
    }

    private func scrollToSelection(_ id: String?, proxy: ScrollViewProxy) {
        guard let id else { return }
        // 不指定 anchor = 最小滚动量露出目标行，等价「就近」语义
        proxy.scrollTo(id)
    }

    // MARK: - Fill bar

    private var fillBar: some View {
        HStack(spacing: 8) {
            Label(L10n.tr("template.fill.title"), systemImage: "text.cursor")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            ForEach(placeholders, id: \.self) { name in
                TextField(name, text: fillBinding(name))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                    .focused($focusedFillField, equals: name)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PasteMemoVisualStyle.subtleFill)
    }

    // MARK: - Rows

    private func row(_ template: TemplateSnippet) -> some View {
        let isSelected = template.templateID == selectedTemplate?.templateID
        return Button {
            handleRowClick(template)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: template.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.22) : PasteMemoVisualStyle.subtleFill,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(of: template))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(renderedFirstLine(of: template))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let shortcut = shortcutIndex(of: template) {
                    keycap("⌘\(shortcut)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    /// 与剪贴板条目一致：单击选中，双击直接粘贴。
    private func handleRowClick(_ template: TemplateSnippet) {
        let now = Date()
        let isDoubleClick = lastClickedID == template.templateID
            && now.timeIntervalSince(lastClickTime) < 0.3

        if isDoubleClick {
            selectedTemplateID = template.templateID
            confirmPaste(cmdOnly: false)
            lastClickedID = nil
            lastClickTime = .distantPast
        } else {
            selectedTemplateID = template.templateID
            lastClickedID = template.templateID
            lastClickTime = now
        }
    }

    private func displayName(of template: TemplateSnippet) -> String {
        template.name.isEmpty ? L10n.tr("template.untitled") : template.name
    }

    private func renderedFirstLine(of template: TemplateSnippet) -> String {
        let rendered = TemplateActions.renderedText(template, fills: fillValues)
        let first = rendered
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? " " : first
    }

    private func shortcutIndex(of template: TemplateSnippet) -> Int? {
        for (index, candidate) in filtered.enumerated() where candidate.templateID == template.templateID {
            return index < 9 ? index + 1 : nil
        }
        return nil
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 4))
    }

    private func fillBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { fillValues[name] ?? "" },
            set: { fillValues[name] = $0 }
        )
    }

    // MARK: - Keyboard model

    private func registerKeyHandlers() {
        coordinator.moveSelection = { delta in moveSelection(delta) }
        coordinator.confirm = { cmdOnly in confirmPaste(cmdOnly: cmdOnly) }
        coordinator.shortcutPaste = { digit in shortcutPaste(digit) }
        coordinator.advanceFillFocus = { advanceFillFocus() }
    }

    private func moveSelection(_ delta: Int) {
        let visible = filtered
        guard !visible.isEmpty else { return }
        let currentID = selectedTemplate?.templateID ?? ""
        var index = 0
        for (position, template) in visible.enumerated() where template.templateID == currentID {
            index = position
            break
        }
        let next = min(max(index + delta, 0), visible.count - 1)
        selectedTemplateID = visible[next].templateID
    }

    private func shortcutPaste(_ digit: Int) {
        let index = digit - 1
        guard index < filtered.count else { return }
        selectedTemplateID = filtered[index].templateID
        confirmPaste(cmdOnly: false)
    }

    private func advanceFillFocus() -> Bool {
        guard !placeholders.isEmpty else { return false }
        let current = focusedFillField ?? ""
        let index = placeholders.firstIndex(of: current) ?? -1
        focusedFillField = placeholders[(index + 1) % placeholders.count]
        return true
    }

    // MARK: - Paste

    private func confirmPaste(cmdOnly: Bool) {
        guard let template = selectedTemplate else { return }
        QuickPanelWindowController.shared.refreshTargetFocusIfPinned()
        if cmdOnly || !quickPanelAutoPaste {
            TemplateActions.copy(template, fills: fillValues)
            if !QuickPanelWindowController.shared.isPinned {
                QuickPanelWindowController.shared.dismiss()
            }
            return
        }
        let text = TemplateActions.renderedText(template, fills: fillValues)
        let wasPinned = QuickPanelWindowController.shared.isPinned
        QuickPanelWindowController.shared.dismissAndPasteText(text, clipboardManager: clipboardManager)
        // 置顶连续快粘不更新 lastUsedAt，状态栏「最近使用」排序保持稳定
        if !wasPinned {
            template.lastUsedAt = Date()
            try? template.modelContext?.save()
        }
    }
}
