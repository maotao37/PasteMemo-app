import SwiftUI

/// 快捷面板条目行组件，集成原生按键键帽与自适应选中态
struct QuickClipRow: View {
    let item: ClipItem
    let isSelected: Bool
    var shortcutIndex: Int? = nil
    var searchText: String = ""
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ClipRow(item: item, isSelected: isSelected, showGroupLabel: false, searchText: searchText, compact: compact)
            Spacer(minLength: 6)
            if let index = shortcutIndex {
                shortcutBadge(index)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 0.75)
                )
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }

    /// 拟物实体键帽样式的快捷键角标
    private func shortcutBadge(_ index: Int) -> some View {
        HStack(spacing: 1) {
            Text("⌘")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
            Text("\(index)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.85))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4.5)
                .fill(Color.primary.opacity(isSelected ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 1, y: 0.5)
        )
    }
}

