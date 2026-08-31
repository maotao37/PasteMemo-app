import SwiftUI

/// 高级毛玻璃卡片容器，提供原生自适应材质与反光微描边
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(padding: CGFloat = 16, cornerRadius: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                if #available(macOS 26.0, *), !reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.22),
                                            Color.white.opacity(0.06),
                                            Color.primary.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.18),
                                            PasteMemoVisualStyle.subtleStroke
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                }
            }
    }
}
