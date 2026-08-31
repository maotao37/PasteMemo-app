import SwiftUI

/// Unified visual representation for every toast PasteMemo shows — simple
/// "Copied" confirmations, undo-style "Deleted 1 item · Undo", Relay progress
/// hints, etc. Adapted from the original `ClipItemUndoToast` palette so every
/// toast surface looks like the undo pill users already know.
struct UnifiedToastView: View {
    let descriptor: ToastDescriptor
    let onAction: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: 10) {
            if let iconName = descriptor.icon.systemImageName {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(descriptor.icon.tint(isDark: isDark))
            }
            Text(descriptor.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
            if let action = descriptor.action {
                actionButton(action)
            }
        }
        // 统一不同内容下 Toast 胶囊的高度与内边距，保持视觉稳定性
        .frame(minHeight: 24)
        .padding(.horizontal, 15)
        .padding(.vertical, 8.5)
        .background {
            toastSurface
                .shadow(color: shadowColor, radius: 16, y: 6)
                .shadow(color: shadowColor.opacity(0.4), radius: 4, y: 1)
        }
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.8),
                            isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .fixedSize()
    }

    private func actionButton(_ action: ToastAction) -> some View {
        HStack(spacing: 4) {
            Text(action.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(actionColor)
            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(actionColor.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(actionBackground, in: Capsule())
        .overlay(Capsule().stroke(actionStroke, lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture { onAction?() }
        .padding(.leading, 2)
    }

    // MARK: - Palette

    @ViewBuilder
    private var toastSurface: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var textColor: Color {
        .primary
    }
    private var actionColor: Color {
        .accentColor
    }
    private var actionBackground: Color {
        Color.accentColor.opacity(isDark ? 0.18 : 0.10)
    }
    private var actionStroke: Color {
        Color.accentColor.opacity(isDark ? 0.24 : 0.12)
    }
    private var shadowColor: Color {
        isDark ? Color.black.opacity(0.48) : Color.black.opacity(0.14)
    }
}

// MARK: - Descriptor types

/// Immutable description of one toast. Passed to `ToastCenter.show(_:)` which
/// then owns rendering, positioning and auto-dismiss timing.
struct ToastDescriptor: Equatable {
    let message: String
    let icon: ToastIcon
    let action: ToastAction?
    /// Auto-dismiss interval. `nil` = panel stays visible until dismiss() is
    /// called explicitly (used by undo toasts which manage their own window).
    let duration: TimeInterval?

    init(
        message: String,
        icon: ToastIcon = .none,
        action: ToastAction? = nil,
        duration: TimeInterval? = 1.5
    ) {
        self.message = message
        self.icon = icon
        self.action = action
        self.duration = duration
    }
}

enum ToastIcon: Equatable {
    case none
    /// Green circle check — for confirmations (copied, saved, deleted, etc.).
    case success
    /// Neutral info glyph, used sparingly for status-style messages.
    case info

    var systemImageName: String? {
        switch self {
        case .none: nil
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    func tint(isDark: Bool) -> Color {
        switch self {
        case .none: .clear
        case .success: PasteMemoVisualStyle.success
        case .info: .accentColor
        }
    }
}

struct ToastAction: Equatable {
    let title: String
    /// Optional keyboard shortcut hint rendered next to the button label
    /// (e.g. `"⌘Z"`). The shortcut itself is wired up by the caller; this is
    /// purely the visual hint.
    let shortcut: String?

    static func == (lhs: ToastAction, rhs: ToastAction) -> Bool {
        lhs.title == rhs.title && lhs.shortcut == rhs.shortcut
    }
}
