import AppKit
import SwiftData
import SwiftUI

@MainActor
enum TemplateActions {
    static func renderedText(_ template: TemplateSnippet) -> String {
        TemplateRenderer.render(
            template.content,
            context: TemplateContext(
                name: UserDefaults.standard.string(forKey: "templateProfileName") ?? "",
                project: UserDefaults.standard.string(forKey: "templateProjectName") ?? "",
                clipboard: NSPasteboard.general.string(forType: .string) ?? ""
            )
        )
    }

    static func copy(_ template: TemplateSnippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(renderedText(template), forType: .string)
        pasteboard.markAsPasteMemoWrite()
        ClipboardManager.shared.lastChangeCount = pasteboard.changeCount
        ToastCenter.shared.show(ToastDescriptor(message: L10n.tr("action.copied"), icon: .success))
    }
}

struct QuickTemplateMenuContent: View {
    @Query(
        filter: #Predicate<TemplateSnippet> { $0.isQuickAccess },
        sort: \TemplateSnippet.sortOrder
    ) private var templates: [TemplateSnippet]

    var body: some View {
        if templates.isEmpty {
            Text(L10n.tr("template.empty"))
        } else {
            ForEach(templates) { template in
                Button(template.name) { TemplateActions.copy(template) }
            }
        }
    }
}

struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TemplateSnippet.sortOrder) private var templates: [TemplateSnippet]
    @AppStorage("templateProfileName") private var profileName = ""
    @AppStorage("templateProjectName") private var projectName = ""
    @State private var selectedTemplateID: String?

    private var selectedTemplate: TemplateSnippet? {
        guard let selectedTemplateID else { return templates.first }
        return templates.first { $0.templateID == selectedTemplateID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTemplateID) {
                ForEach(templates) { template in
                    Label(template.name, systemImage: template.icon)
                        .tag(template.templateID)
                        .contextMenu {
                            Button(L10n.tr("action.delete"), role: .destructive) {
                                delete(template)
                            }
                        }
                }
                .onMove(perform: moveTemplates)
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("template.empty"),
                        systemImage: "text.badge.plus",
                        description: Text(L10n.tr("template.empty.help"))
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { addTemplate() } label: { Image(systemName: "plus") }
                        .help(L10n.tr("template.new"))
                    Button {
                        if let selectedTemplate { delete(selectedTemplate) }
                    } label: { Image(systemName: "minus") }
                    .disabled(selectedTemplate == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            if let template = selectedTemplate {
                templateEditor(template)
            } else {
                ContentUnavailableView(L10n.tr("template.select"), systemImage: "text.cursor")
            }
        }
        .navigationTitle(L10n.tr("settings.templates"))
        .onAppear { selectedTemplateID = selectedTemplateID ?? templates.first?.templateID }
    }

    private func templateEditor(_ template: TemplateSnippet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField(L10n.tr("template.name"), text: bind(template, \.name))
                    .font(.title3.weight(.semibold))
                Toggle(L10n.tr("group.quickAccess"), isOn: bind(template, \.isQuickAccess))
                    .toggleStyle(.switch)
            }

            HStack {
                TextField(L10n.tr("template.profileName"), text: $profileName)
                TextField(L10n.tr("template.project"), text: $projectName)
            }

            Text(L10n.tr("template.content"))
                .font(.headline)
            TextEditor(text: bind(template, \.content))
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PasteMemoVisualStyle.subtleStroke))
                .frame(minHeight: 150)

            HStack(spacing: 6) {
                ForEach(TemplateRenderer.supportedVariables, id: \.self) { variable in
                    Button("{{\(variable)}}") {
                        template.content += "{{\(variable)}}"
                        save(template)
                    }
                    .controlSize(.small)
                }
            }

            Text(L10n.tr("template.preview"))
                .font(.headline)
            ScrollView {
                Text(rendered(template))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(minHeight: 90)
            .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button {
                    copyRendered(template)
                } label: {
                    Label(L10n.tr("template.copyRendered"), systemImage: "doc.on.doc")
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(20)
        .onDisappear { try? modelContext.save() }
    }

    private func bind<T>(_ template: TemplateSnippet, _ keyPath: ReferenceWritableKeyPath<TemplateSnippet, T>) -> Binding<T> {
        Binding(
            get: { template[keyPath: keyPath] },
            set: {
                template[keyPath: keyPath] = $0
                template.updatedAt = Date()
                save(template)
            }
        )
    }

    private func rendered(_ template: TemplateSnippet) -> String {
        TemplateActions.renderedText(template)
    }

    private func copyRendered(_ template: TemplateSnippet) {
        TemplateActions.copy(template)
    }

    private func addTemplate() {
        let next = (templates.map(\.sortOrder).max() ?? -1) + 1
        let template = TemplateSnippet(
            name: L10n.tr("template.untitled"),
            content: L10n.tr("template.defaultContent"),
            sortOrder: next
        )
        modelContext.insert(template)
        try? modelContext.save()
        selectedTemplateID = template.templateID
    }

    private func delete(_ template: TemplateSnippet) {
        let index = templates.firstIndex { $0.templateID == template.templateID } ?? 0
        modelContext.delete(template)
        try? modelContext.save()
        let remaining = templates.filter { $0.templateID != template.templateID }
        selectedTemplateID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].templateID
    }

    private func moveTemplates(from offsets: IndexSet, to destination: Int) {
        var reordered = templates
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, template) in reordered.enumerated() { template.sortOrder = index }
        try? modelContext.save()
    }

    private func save(_ template: TemplateSnippet) {
        template.updatedAt = Date()
        try? modelContext.save()
    }
}
