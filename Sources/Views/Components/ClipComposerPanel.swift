import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ClipComposerPanel {
    enum Action {
        case copyOrPaste
        case createClip
    }

    struct Result {
        let orderedItemIDs: [String]
        let content: String
        let action: Action
        let removeOriginals: Bool
    }

    static func show(items: [ClipItem], canPaste: Bool) -> Result? {
        guard items.count > 1 else { return nil }
        let viewModel = ClipComposerViewModel(items: items, canPaste: canPaste)
        let root = ClipComposerView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 600)
        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.tr("composer.title")
        panel.contentView = hostingView
        panel.minSize = NSSize(width: 500, height: 520)
        panel.center()
        panel.isFloatingPanel = true
        panel.level = .modalPanel

        let session = ComposerModalSession(panel: panel)
        panel.delegate = session
        viewModel.onCancel = { session.cancel() }
        viewModel.onConfirm = { session.confirm() }

        guard NSApp.runModal(for: panel) == .OK, let action = viewModel.action else { return nil }
        return Result(
            orderedItemIDs: viewModel.items.map(\.itemID),
            content: viewModel.composedContent,
            action: action,
            removeOriginals: viewModel.removeOriginals
        )
    }
}

@MainActor
private final class ComposerModalSession: NSObject, NSWindowDelegate {
    private weak var panel: NSPanel?
    private var response: NSApplication.ModalResponse?

    init(panel: NSPanel) { self.panel = panel }

    func confirm() { finish(.OK) }
    func cancel() { finish(.cancel) }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: response ?? .cancel)
    }

    private func finish(_ value: NSApplication.ModalResponse) {
        guard response == nil else { return }
        response = value
        guard let panel else {
            NSApp.stopModal(withCode: value)
            return
        }
        panel.close()
    }
}

@MainActor
@Observable
private final class ClipComposerViewModel {
    var items: [ClipItem]
    var separatorRaw = "newline"
    var customSeparator = ""
    var removeOriginals = false
    var draggingID: String?
    let canPaste: Bool
    var action: ClipComposerPanel.Action?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    init(items: [ClipItem], canPaste: Bool) {
        self.items = items
        self.canPaste = canPaste
    }

    var separator: String {
        switch separatorRaw {
        case "space": " "
        case "blankLine": "\n\n"
        case "custom": customSeparator
        default: "\n"
        }
    }

    var composedContent: String { items.map(\.content).joined(separator: separator) }
}

private struct ClipComposerView: View {
    @Bindable var viewModel: ClipComposerViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("composer.title"))
                    .font(.title2.weight(.semibold))
                Text(L10n.tr("composer.help"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)

            Divider()

            HSplitView {
                List {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.itemID) { index, item in
                        HStack(spacing: 9) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Image(systemName: item.contentType.icon)
                                .foregroundStyle(.secondary)
                            Text(item.displayTitle ?? item.content)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onDrag {
                            viewModel.draggingID = item.itemID
                            return NSItemProvider(object: item.itemID as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ComposerDropDelegate(
                            targetID: item.itemID,
                            viewModel: viewModel
                        ))
                    }
                }
                .frame(minWidth: 220)

                ScrollView {
                    Text(viewModel.composedContent)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .frame(minWidth: 240)
            }

            Divider()

            VStack(spacing: 12) {
                HStack {
                    Picker(L10n.tr("composer.separator"), selection: $viewModel.separatorRaw) {
                        Text(L10n.tr("composer.separator.newline")).tag("newline")
                        Text(L10n.tr("composer.separator.blankLine")).tag("blankLine")
                        Text(L10n.tr("composer.separator.space")).tag("space")
                        Text(L10n.tr("composer.separator.custom")).tag("custom")
                    }
                    if viewModel.separatorRaw == "custom" {
                        TextField(L10n.tr("composer.separator.customValue"), text: $viewModel.customSeparator)
                            .frame(width: 140)
                    }
                    Spacer()
                    Text(L10n.tr("composer.characterCount", viewModel.composedContent.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Toggle(L10n.tr("composer.removeOriginals"), isOn: $viewModel.removeOriginals)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button(L10n.tr("action.cancel")) { viewModel.onCancel?() }
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.tr("composer.createClip")) {
                        viewModel.action = .createClip
                        viewModel.onConfirm?()
                    }
                    Button(viewModel.canPaste ? L10n.tr("composer.pasteOnce") : L10n.tr("composer.copyOnce")) {
                        viewModel.action = .copyOrPaste
                        viewModel.onConfirm?()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
        .frame(minWidth: 500, minHeight: 520)
    }
}

@MainActor
private struct ComposerDropDelegate: DropDelegate {
    let targetID: String
    let viewModel: ClipComposerViewModel

    func dropEntered(info: DropInfo) {
        guard let sourceID = viewModel.draggingID, sourceID != targetID,
              let from = viewModel.items.firstIndex(where: { $0.itemID == sourceID }),
              let to = viewModel.items.firstIndex(where: { $0.itemID == targetID }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.items.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
