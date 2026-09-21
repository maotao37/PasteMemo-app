import AppKit
import SwiftData
import SwiftUI

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
                Button {
                    TemplateActions.copy(template)
                } label: {
                    Label(template.name, systemImage: template.icon)
                }
            }
            Divider()
        }
        Button(L10n.tr("template.manage")) {
            AppAction.shared.openSettings?()
        }
    }
}

struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TemplateSnippet.sortOrder) private var templates: [TemplateSnippet]
    @State private var selectedTemplateID: String?
    @State private var searchText = ""
    @State private var pendingDelete: TemplateSnippet?
    @State private var editorBridge = TemplateEditorBridge()

    private var filteredTemplates: [TemplateSnippet] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return templates }
        return templates.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.content.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var selectedTemplate: TemplateSnippet? {
        guard let selectedTemplateID else { return filteredTemplates.first }
        return templates.first { $0.templateID == selectedTemplateID }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let template = selectedTemplate {
                TemplateEditorView(template: template, bridge: editorBridge)
                    .id(template.templateID)
            } else {
                ContentUnavailableView(L10n.tr("template.select"), systemImage: "text.cursor")
            }
        }
        .navigationTitle(L10n.tr("settings.templates"))
        .onAppear { selectedTemplateID = selectedTemplateID ?? templates.first?.templateID }
        .alert(
            pendingDelete.map { String(format: L10n.tr("template.deleteConfirm"), $0.name) } ?? "",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { template in
            Button(L10n.tr("action.delete"), role: .destructive) { delete(template) }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.tr("template.searchPlaceholder"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 6))
            .padding(8)

            List(selection: $selectedTemplateID) {
                ForEach(filteredTemplates) { template in
                    templateRow(template)
                        .tag(template.templateID)
                        .contextMenu {
                            Button(L10n.tr("template.copyRendered")) { TemplateActions.copy(template) }
                            Button(L10n.tr("template.duplicate")) { duplicate(template) }
                            Divider()
                            Button(L10n.tr("action.delete"), role: .destructive) { pendingDelete = template }
                        }
                }
                .onMove { offsets, destination in
                    // While filtering, move offsets index the filtered list — ignore drags.
                    guard searchText.isEmpty else { return }
                    moveTemplates(from: offsets, to: destination)
                }
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("template.empty"),
                        systemImage: "text.badge.plus",
                        description: Text(L10n.tr("template.empty.help"))
                    )
                } else if filteredTemplates.isEmpty {
                    ContentUnavailableView(L10n.tr("template.noMatch"), systemImage: "magnifyingglass")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { addTemplate() } label: { Image(systemName: "plus") }
                        .help(L10n.tr("template.new"))
                    Button {
                        if let selectedTemplate { pendingDelete = selectedTemplate }
                    } label: { Image(systemName: "minus") }
                    .disabled(selectedTemplate == nil)
                    Button {
                        if let selectedTemplate { duplicate(selectedTemplate) }
                    } label: { Image(systemName: "doc.on.doc") }
                    .disabled(selectedTemplate == nil)
                    .help(L10n.tr("template.duplicate"))
                    Spacer()
                    Text(L10n.tr("template.count", templates.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(8)
                .background(.bar)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
    }

    private func templateRow(_ template: TemplateSnippet) -> some View {
        HStack(spacing: 8) {
            Image(systemName: template.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(of: template))
                    .lineLimit(1)
                Text(summary(of: template))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func displayName(of template: TemplateSnippet) -> String {
        template.name.isEmpty ? L10n.tr("template.untitled") : template.name
    }

    private func summary(of template: TemplateSnippet) -> String {
        let firstLine = template.content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? " " : firstLine
    }

    // MARK: - Actions

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

    private func duplicate(_ template: TemplateSnippet) {
        let copy = TemplateSnippet(
            name: template.name + " " + L10n.tr("template.duplicate.suffix"),
            content: template.content,
            icon: template.icon,
            sortOrder: 0,
            isQuickAccess: template.isQuickAccess
        )
        modelContext.insert(copy)
        var ordered = templates
        if let index = ordered.firstIndex(where: { $0.templateID == template.templateID }) {
            ordered.insert(copy, at: index + 1)
            for (position, item) in ordered.enumerated() { item.sortOrder = position }
        } else {
            copy.sortOrder = (ordered.map(\.sortOrder).max() ?? -1) + 1
        }
        try? modelContext.save()
        selectedTemplateID = copy.templateID
    }

    private func moveTemplates(from offsets: IndexSet, to destination: Int) {
        var reordered = templates
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, template) in reordered.enumerated() { template.sortOrder = index }
        try? modelContext.save()
    }
}

// MARK: - Editor

private struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let template: TemplateSnippet
    let bridge: TemplateEditorBridge

    @AppStorage("templateProfileName") private var profileName = ""
    @AppStorage("templateProjectName") private var projectName = ""
    @State private var fillValues: [String: String] = [:]
    @State private var showIconPicker = false
    @State private var showProfile = false
    @FocusState private var nameFieldFocused: Bool

    private var placeholders: [String] {
        TemplateRenderer.placeholderNames(in: template.content)
    }

    private var renderedText: String {
        TemplateActions.renderedText(template, fills: fillValues)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                profileSection
                contentSection
                variableChips
                if !placeholders.isEmpty { fillSection }
                previewSection
                actionBar
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if template.name.isEmpty || template.name == L10n.tr("template.untitled") {
                DispatchQueue.main.async { nameFieldFocused = true }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Button {
                showIconPicker = true
            } label: {
                Image(systemName: template.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 30)
                    .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(PasteMemoVisualStyle.subtleStroke))
            }
            .buttonStyle(.plain)
            .help(L10n.tr("template.icon"))
            .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                TemplateIconPicker(icon: bind(\.icon))
            }

            TextField(L10n.tr("template.name"), text: bind(\.name))
                .font(.title3.weight(.semibold))
                .focused($nameFieldFocused)

            Toggle(L10n.tr("group.quickAccess"), isOn: bind(\.isQuickAccess))
                .toggleStyle(.switch)
        }
    }

    private var profileSection: some View {
        DisclosureGroup(isExpanded: $showProfile) {
            HStack(spacing: 10) {
                TextField(L10n.tr("template.profileName"), text: $profileName)
                TextField(L10n.tr("template.project"), text: $projectName)
            }
            .padding(.top, 6)
        } label: {
            Label(L10n.tr("template.profileSection"), systemImage: "person.crop.circle")
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("template.content"))
                .font(.headline)
            TemplateContentEditor(text: bind(\.content), bridge: bridge)
                .frame(minHeight: 210)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PasteMemoVisualStyle.subtleStroke))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var variableChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            chipRow(title: L10n.tr("template.variables.datetime"), variables: ["time", "datetime"]) {
                dateMenu
                chip("{{date}}")
            }
            chipRow(title: L10n.tr("template.variables.personal"), variables: ["name", "project"]) {}
            chipRow(title: L10n.tr("template.variables.clipboard"), variables: ["clipboard"]) {}
        }
    }

    private var dateMenu: some View {
        Menu {
            ForEach(datePresetTokens, id: \.self) { token in
                Button("\(token)  ·  \(example(for: token))") {
                    bridge.insert(token)
                }
            }
        } label: {
            Text("{{date}}")
        }
        .controlSize(.small)
        .fixedSize()
    }

    private var datePresetTokens: [String] {
        ["{{date}}", "{{date:yyyy-MM-dd}}", "{{date:yyyy/M/d}}", "{{date:yyyy年M月d日}}"]
    }

    private func example(for token: String) -> String {
        TemplateRenderer.render(token, context: TemplateContext())
    }

    private func chipRow(
        title: String,
        variables: [String],
        @ViewBuilder extra: () -> some View
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            extra()
            ForEach(variables, id: \.self) { variable in
                chip("{{\(variable)}}")
            }
        }
    }

    private func chip(_ token: String) -> some View {
        Button(token) {
            bridge.insert(token)
        }
        .controlSize(.small)
    }

    private var fillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("template.fill.title"))
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(placeholders, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        TextField(String(format: "{{%@}}", name), text: fillBinding(name))
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("template.preview"))
                    .font(.headline)
                Spacer()
                Text(L10n.tr(
                    "template.metrics",
                    renderedText.count,
                    renderedText.components(separatedBy: .newlines).count
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            ScrollView {
                Text(renderedText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(minHeight: 90)
            .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 6))
            Text(L10n.tr("template.preview.source"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            Button {
                TemplateActions.copy(template, fills: fillValues)
            } label: {
                Label(L10n.tr("template.copyRendered"), systemImage: "doc.on.doc")
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<TemplateSnippet, T>) -> Binding<T> {
        Binding(
            get: { template[keyPath: keyPath] },
            set: {
                template[keyPath: keyPath] = $0
                save()
            }
        )
    }

    private func fillBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { fillValues[name] ?? "" },
            set: { fillValues[name] = $0 }
        )
    }

    private func save() {
        template.updatedAt = Date()
        try? modelContext.save()
    }
}
