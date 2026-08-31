import AppKit
import SwiftUI

/// Modal panel for creating/editing a group (name + categorized icon picker)
@MainActor
final class GroupEditorPanel {

    struct Result {
        let name: String
        let icon: String
        let preservesItems: Bool
        let color: String?
        let layoutRaw: String
        let isQuickAccess: Bool
        let kindRaw: String
        let smartFilter: SmartGroupFilter
    }

    static func show(
        name: String = "",
        icon: String = "folder",
        preservesItems: Bool = false,
        color: String? = nil,
        layoutRaw: String = PinboardLayout.list.rawValue,
        isQuickAccess: Bool = false,
        isSmart: Bool = false,
        smartFilter: SmartGroupFilter = SmartGroupFilter()
    ) -> Result? {
        let height: CGFloat = isSmart ? 690 : 560
        let viewModel = GroupEditorViewModel(
            name: name,
            icon: icon,
            preservesItems: preservesItems,
            color: color,
            layoutRaw: layoutRaw,
            isQuickAccess: isQuickAccess,
            isSmart: isSmart,
            smartFilter: smartFilter
        )
        let hostingView = NSHostingView(rootView: GroupEditorView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        panel.title = isSmart
            ? L10n.tr(name.isEmpty ? "menu.newSmartGroup" : "group.editSmart")
            : L10n.tr(name.isEmpty ? "action.newGroup" : "action.editGroup")
        panel.contentView = hostingView
        panel.center()
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        let session = ModalSession(panel: panel)
        panel.delegate = session

        viewModel.onDismiss = { session.cancel() }
        viewModel.onConfirm = { session.confirm() }

        let response = NSApp.runModal(for: panel)
        guard response == .OK else { return nil }
        let resultName = viewModel.name.trimmingCharacters(in: .whitespaces)
        guard !resultName.isEmpty else { return nil }
        return Result(
            name: resultName,
            icon: viewModel.selectedIcon,
            preservesItems: viewModel.preservesItems,
            color: viewModel.selectedColor,
            layoutRaw: viewModel.layoutRaw,
            isQuickAccess: viewModel.isQuickAccess,
            kindRaw: viewModel.isSmart ? "smart" : "manual",
            smartFilter: viewModel.smartFilter
        )
    }
}

@MainActor
private final class ModalSession: NSObject, NSWindowDelegate {
    private weak var panel: NSPanel?
    private var response: NSApplication.ModalResponse?

    init(panel: NSPanel) {
        self.panel = panel
    }

    func confirm() {
        finish(.OK)
    }

    func cancel() {
        finish(.cancel)
    }

    func windowWillClose(_ notification: Notification) {
        let finalResponse = response ?? .cancel
        response = finalResponse
        NSApp.stopModal(withCode: finalResponse)
    }

    private func finish(_ modalResponse: NSApplication.ModalResponse) {
        guard response == nil else { return }
        response = modalResponse
        guard let panel else {
            NSApp.stopModal(withCode: modalResponse)
            return
        }
        panel.close()
    }
}

// MARK: - ViewModel

@Observable
private class GroupEditorViewModel {
    var name: String
    var selectedIcon: String
    var preservesItems: Bool
    var selectedColor: String?
    var layoutRaw: String
    var isQuickAccess: Bool
    let isSmart: Bool
    var smartQuery: String
    var smartContentTypeRaw: String?
    var smartSourceApp: String
    var smartFlagRaw: String
    var smartRecentDays: Int
    var smartMatchModeRaw: String
    var iconSearchText = ""
    var selectedCategory: IconCategory

    var onDismiss: (() -> Void)?
    var onConfirm: (() -> Void)?

    init(
        name: String,
        icon: String,
        preservesItems: Bool,
        color: String?,
        layoutRaw: String,
        isQuickAccess: Bool,
        isSmart: Bool,
        smartFilter: SmartGroupFilter
    ) {
        self.name = name
        self.selectedIcon = icon
        self.preservesItems = preservesItems
        self.selectedColor = color
        self.layoutRaw = layoutRaw
        self.isQuickAccess = isQuickAccess
        self.isSmart = isSmart
        self.smartQuery = smartFilter.query
        self.smartContentTypeRaw = smartFilter.contentTypeRaw
        self.smartSourceApp = smartFilter.sourceApp
        self.smartFlagRaw = smartFilter.flagRaw
        self.smartRecentDays = smartFilter.recentDays
        self.smartMatchModeRaw = smartFilter.matchModeRaw
        self.selectedCategory = IconCategory.all[0]
    }

    var smartFilter: SmartGroupFilter {
        SmartGroupFilter(
            query: smartQuery,
            contentTypeRaw: smartContentTypeRaw,
            sourceApp: smartSourceApp,
            flagRaw: smartFlagRaw,
            recentDays: smartRecentDays,
            matchModeRaw: smartMatchModeRaw
        )
    }

    var filteredIcons: [String] {
        if !iconSearchText.isEmpty {
            // Search across all categories
            let allIcons = IconCategory.all[0].icons
            return allIcons.filter { $0.localizedCaseInsensitiveContains(iconSearchText) }
        }
        return selectedCategory.icons
    }

    var isConfirmDisabled: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty || (isSmart && !smartFilter.hasConditions)
    }
}

// MARK: - Icon Categories

private struct IconCategory: Identifiable, Hashable {
    let id: String
    let label: String
    let icons: [String]

    static let all: [IconCategory] = {
        let cats = categories
        let allIcons = IconCategory(id: "all", label: "全部", icons: cats.flatMap(\.icons))
        return [allIcons] + cats
    }()

    private static let categories: [IconCategory] = [
        IconCategory(id: "file", label: "文件", icons: [
            "folder", "folder.fill", "tray", "tray.full", "tray.2",
            "archivebox", "archivebox.fill", "doc", "doc.fill", "doc.text", "doc.text.fill",
            "note.text", "list.bullet", "list.clipboard", "square.stack",
        ]),
        IconCategory(id: "mark", label: "标记", icons: [
            "bookmark", "bookmark.fill", "tag", "tag.fill",
            "star", "star.fill", "heart", "heart.fill",
            "flag", "flag.fill", "pin", "pin.fill",
            "rosette", "seal", "seal.fill", "bell", "bell.fill",
        ]),
        IconCategory(id: "work", label: "工作", icons: [
            "briefcase", "briefcase.fill", "building.2", "building.2.fill",
            "storefront", "storefront.fill", "house", "house.fill",
            "calendar", "clock", "timer", "hourglass",
            "chart.bar", "chart.bar.fill", "chart.pie", "chart.pie.fill",
            "chart.line.uptrend.xyaxis", "target", "scope",
        ]),
        IconCategory(id: "person", label: "人物", icons: [
            "person", "person.fill", "person.2", "person.2.fill",
            "person.crop.circle", "figure.walk", "figure.run",
            "graduationcap", "graduationcap.fill", "brain", "brain.head.profile",
        ]),
        IconCategory(id: "comm", label: "通信", icons: [
            "globe", "globe.americas", "link", "link.circle",
            "envelope", "envelope.fill", "phone", "phone.fill",
            "bubble.left", "bubble.left.fill", "bubble.right", "bubble.right.fill",
            "wifi", "network", "antenna.radiowaves.left.and.right",
        ]),
        IconCategory(id: "media", label: "媒体", icons: [
            "camera", "camera.fill", "photo", "photo.fill",
            "music.note", "music.note.list", "film", "video", "video.fill",
            "paintbrush", "paintbrush.fill", "paintpalette", "paintpalette.fill",
            "pencil", "pencil.circle", "eyedropper", "eyedropper.full",
            "highlighter", "theatermasks", "theatermasks.fill",
        ]),
        IconCategory(id: "tool", label: "工具", icons: [
            "wrench", "wrench.fill", "gear", "gearshape",
            "hammer", "hammer.fill", "screwdriver", "screwdriver.fill",
            "slider.horizontal.3", "tuningfork",
            "terminal", "terminal.fill", "chevron.left.forwardslash.chevron.right",
            "cpu", "memorychip", "externaldrive", "internaldrive",
        ]),
        IconCategory(id: "nature", label: "自然", icons: [
            "leaf", "leaf.fill", "flame", "flame.fill",
            "drop", "drop.fill", "bolt", "bolt.fill",
            "sun.max", "sun.max.fill", "moon", "moon.fill",
            "cloud", "cloud.fill", "snowflake", "wind",
            "sparkles", "sparkle",
        ]),
        IconCategory(id: "shop", label: "购物", icons: [
            "cart", "cart.fill", "bag", "bag.fill",
            "creditcard", "creditcard.fill", "banknote", "banknote.fill",
            "gift", "gift.fill", "dollarsign.circle", "dollarsign.circle.fill",
            "yensign.circle", "yensign.circle.fill",
        ]),
        IconCategory(id: "travel", label: "出行", icons: [
            "airplane", "car", "car.fill", "bicycle",
            "bus", "tram", "ferry",
            "map", "map.fill", "location", "location.fill",
            "compass.drawing", "binoculars", "suitcase", "suitcase.fill",
        ]),
        IconCategory(id: "fun", label: "娱乐", icons: [
            "gamecontroller", "gamecontroller.fill", "sportscourt",
            "trophy", "trophy.fill", "medal", "medal.fill",
            "puzzlepiece", "puzzlepiece.fill",
            "headphones", "guitars", "guitars.fill", "music.mic",
            "dice", "dice.fill",
        ]),
        IconCategory(id: "health", label: "安全", icons: [
            "heart.text.square", "cross.case", "cross.case.fill",
            "shield", "shield.fill", "lock", "lock.fill",
            "key", "key.fill", "hand.raised", "hand.raised.fill",
            "eye", "eye.fill", "faceid",
        ]),
        IconCategory(id: "food", label: "饮食", icons: [
            "cup.and.saucer", "cup.and.saucer.fill",
            "fork.knife", "birthday.cake",
            "wineglass", "wineglass.fill",
            "mug", "mug.fill", "waterbottle", "waterbottle.fill",
        ]),
    ]
}

// MARK: - SwiftUI View

private struct GroupEditorView: View {
    @Bindable var viewModel: GroupEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            if viewModel.isSmart {
                smartCriteriaSection
                Divider()
            }
            iconPickerSection
            Divider()
            footerSection
        }
        .frame(width: 420, height: viewModel.isSmart ? 690 : 560)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.selectedIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                TextField(L10n.tr("automation.action.assignGroup.placeholder"), text: $viewModel.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
            }

            if !viewModel.isSmart {
                Toggle(isOn: $viewModel.preservesItems) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("group.preserveItems"))
                        Text(L10n.tr("group.preserveItems.help"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Toggle(L10n.tr("group.quickAccess"), isOn: $viewModel.isQuickAccess)
                .toggleStyle(.switch)

            HStack(spacing: 10) {
                Text(L10n.tr("group.color"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.selectedColor = nil
                } label: {
                    Image(systemName: "circle.slash")
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                ForEach(SmartGroup.availableColors, id: \.self) { hex in
                    Button {
                        viewModel.selectedColor = hex
                    } label: {
                        Circle()
                            .fill(Color.pasteMemo(hex: hex) ?? .accentColor)
                            .frame(width: 20, height: 20)
                            .overlay {
                                if viewModel.selectedColor == hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker(L10n.tr("group.layout"), selection: $viewModel.layoutRaw) {
                ForEach(PinboardLayout.allCases, id: \.rawValue) { layout in
                    Label(layout.title, systemImage: layout.icon).tag(layout.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
    }

    private var smartCriteriaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("group.smart.conditions"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: $viewModel.smartMatchModeRaw) {
                    Text(L10n.tr("group.smart.matchAll")).tag(SmartGroupMatchMode.all.rawValue)
                    Text(L10n.tr("group.smart.matchAny")).tag(SmartGroupMatchMode.any.rawValue)
                }
                .labelsHidden()
                .frame(width: 130)
            }
            TextField(L10n.tr("group.smart.keyword"), text: $viewModel.smartQuery)
            HStack {
                Picker(L10n.tr("group.smart.type"), selection: $viewModel.smartContentTypeRaw) {
                    Text(L10n.tr("group.smart.anyType")).tag(nil as String?)
                    ForEach(ClipContentType.ruleEditorVisibleCases, id: \.rawValue) { type in
                        Text(type.label).tag(type.rawValue as String?)
                    }
                }
                TextField(L10n.tr("group.smart.sourceApp"), text: $viewModel.smartSourceApp)
            }
            HStack {
                Picker(L10n.tr("group.smart.status"), selection: $viewModel.smartFlagRaw) {
                    Text(L10n.tr("group.smart.anyStatus")).tag(SmartGroupFlag.any.rawValue)
                    Text(L10n.tr("filter.pinned")).tag(SmartGroupFlag.pinned.rawValue)
                    Text(L10n.tr("group.smart.favorite")).tag(SmartGroupFlag.favorite.rawValue)
                    Text(L10n.tr("filter.sensitive")).tag(SmartGroupFlag.sensitive.rawValue)
                }
                Stepper(
                    viewModel.smartRecentDays > 0
                        ? L10n.tr("group.smart.recentDays", viewModel.smartRecentDays)
                        : L10n.tr("group.smart.anyTime"),
                    value: $viewModel.smartRecentDays,
                    in: 0...365
                )
            }
            Text(L10n.tr("group.smart.help"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var iconPickerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Search icons...", text: $viewModel.iconSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !viewModel.iconSearchText.isEmpty {
                    Button { viewModel.iconSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            if viewModel.iconSearchText.isEmpty {
                categoryTabs
                Divider()
            }
            iconGrid
        }
        .frame(maxHeight: .infinity)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(IconCategory.all) { category in
                    Button {
                        viewModel.selectedCategory = category
                    } label: {
                        Text(category.label)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.selectedCategory == category
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                viewModel.selectedCategory == category
                                    ? Color.accentColor
                                    : .secondary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var iconGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                ForEach(viewModel.filteredIcons, id: \.self) { symbol in
                    Button {
                        viewModel.selectedIcon = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(
                                viewModel.selectedIcon == symbol ? .white : .primary
                            )
                            .background(
                                viewModel.selectedIcon == symbol
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var footerSection: some View {
        HStack {
            Spacer()
            Button(L10n.tr("action.cancel")) {
                viewModel.onDismiss?()
            }
            .keyboardShortcut(.cancelAction)
            Button(L10n.tr("action.confirm")) {
                viewModel.onConfirm?()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isConfirmDisabled)
        }
        .padding(12)
    }
}
