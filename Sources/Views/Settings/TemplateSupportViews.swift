import AppKit
import SwiftUI

/// Lets variable chips insert text at the caret of the shared content editor
/// even though the editor itself is an NSViewRepresentable.
@MainActor
final class TemplateEditorBridge: ObservableObject {
    var insertHandler: ((String) -> Void)?

    func insert(_ snippet: String) {
        insertHandler?(snippet)
    }
}

/// Monospaced plain-text editor with live `{{variable}}` highlighting.
struct TemplateContentEditor: NSViewRepresentable {
    @Binding var text: String
    let bridge: TemplateEditorBridge

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TemplateTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let coordinator = context.coordinator
        bridge.insertHandler = { [weak coordinator] snippet in
            coordinator?.insert(snippet)
        }
        guard let view = scrollView.documentView as? TemplateTextView else { return }
        if view.string != text {
            view.string = text
            view.highlightVariables()
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        (nsView.documentView as? TemplateTextView)?.delegate = nil
        coordinator.textView = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TemplateContentEditor
        weak var textView: TemplateTextView?

        init(_ parent: TemplateContentEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? TemplateTextView else { return }
            view.highlightVariables()
            parent.text = view.string
        }

        /// Replaces the current selection (or the caret) with the snippet and
        /// leaves the caret just after it, ready for further typing.
        func insert(_ snippet: String) {
            guard let textView, let storage = textView.textStorage else { return }
            let selected = textView.selectedRange()
            let location = min(max(0, selected.location), storage.length)
            let length = min(selected.length, storage.length - location)
            storage.replaceCharacters(in: NSRange(location: location, length: length), with: snippet)
            textView.setSelectedRange(NSRange(location: location + (snippet as NSString).length, length: 0))
            textView.highlightVariables()
            parent.text = textView.string
        }
    }
}

final class TemplateTextView: NSTextView {
    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.labelColor,
    ]

    private let variableRegex = try! NSRegularExpression(pattern: #"\{\{[^:}]*(:[^}]*)?\}\}"#)

    convenience init() {
        self.init(frame: .zero)
        allowsUndo = true
        isRichText = false
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        font = Self.baseAttributes[.font] as? NSFont
        typingAttributes = Self.baseAttributes
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainerInset = NSSize(width: 8, height: 10)
        isEditable = true
        isSelectable = true
    }

    func highlightVariables() {
        // 如果当前处于输入法组合态（拼音/候选词未落字），跳过属性重绘，避免打断系统输入法下划线样式
        guard !hasMarkedText() else { return }
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes, range: full)
        for match in variableRegex.matches(in: string, range: full) {
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: match.range)
        }
        storage.endEditing()
    }
}

/// Popover grid of curated SF Symbols for the template list row.
struct TemplateIconPicker: View {
    @Binding var icon: String
    @State private var search = ""

    static let curatedIcons: [String] = [
        "text.badge.plus", "doc.text", "doc.on.doc", "doc.richtext", "square.and.pencil",
        "paperplane", "envelope", "message", "bubble.left", "bubble.left.and.bubble.right",
        "phone", "person", "person.2", "person.crop.circle", "briefcase",
        "folder", "clipboard", "scissors", "wrench", "screwdriver",
        "gearshape", "hammer", "printer", "bookmark", "flag",
        "star", "heart", "moon", "sun.max", "clock",
        "calendar", "timer", "map", "mappin", "airplane",
        "cart", "creditcard", "dollarsign", "yensign", "chart.bar",
        "chart.pie", "graduationcap", "book", "newspaper", "lightbulb",
        "tag", "gift", "globe", "network", "link",
        "keyboard", "terminal", "curlybraces", "number", "exclamationmark.bubble",
        "checkmark.seal", "paintbrush", "camera", "video", "music.note",
        "mic", "headphones", "gamecontroller", "leaf", "flame",
        "drop", "bolt",
    ]

    private var filtered: [String] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Self.curatedIcons }
        return Self.curatedIcons.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField(L10n.tr("template.searchIcons"), text: $search)
                .controlSize(.small)
                .padding(4)
                .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 4), count: 7), spacing: 6) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            icon = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 15))
                                .frame(width: 34, height: 26)
                                .foregroundStyle(icon == name ? Color.accentColor : .primary)
                                .background(
                                    icon == name ? Color.accentColor.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 328, height: 330)
        .padding(12)
    }
}
