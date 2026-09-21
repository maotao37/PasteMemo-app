import SwiftData
import SwiftUI

/// 「存为模板」的草稿：从剪贴板条目一键带出名称（首行截断）与内容。
struct SaveAsTemplateDraft: Identifiable {
    let id = UUID()
    var name: String
    var content: String

    init(sourceItem item: ClipItem) {
        let firstLine = item.content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = String(firstLine.prefix(24))
        self.content = item.content
    }

    init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}

/// 轻量的「存为模板」确认表单：名称可改，内容可继续插变量。
struct SaveAsTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let draft: SaveAsTemplateDraft

    @State private var name: String
    @State private var content: String

    init(draft: SaveAsTemplateDraft) {
        self.draft = draft
        _name = State(initialValue: draft.name)
        _content = State(initialValue: draft.content)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("action.saveAsTemplate"))
                .font(.headline)

            TextField(L10n.tr("template.name"), text: $name)

            Text(L10n.tr("template.content"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PasteMemoVisualStyle.subtleStroke))

            HStack {
                Text(L10n.tr("template.saveAsHint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(L10n.tr("action.cancel"), role: .cancel) { dismiss() }
                Button(L10n.tr("action.save")) { save() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func save() {
        guard canSave else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<TemplateSnippet>())) ?? []
        let maxOrder = existing.map(\.sortOrder).max() ?? -1
        let template = TemplateSnippet(
            name: name.trimmingCharacters(in: .whitespaces),
            content: content,
            sortOrder: maxOrder + 1
        )
        modelContext.insert(template)
        try? modelContext.save()
        ToastCenter.shared.show(ToastDescriptor(message: L10n.tr("template.saved"), icon: .success))
        dismiss()
    }
}
