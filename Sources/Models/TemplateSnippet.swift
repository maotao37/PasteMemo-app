import Foundation
import SwiftData

@Model
final class TemplateSnippet {
    var templateID: String = UUID().uuidString
    var name: String = ""
    var content: String = ""
    var icon: String = "text.badge.plus"
    var sortOrder: Int = 0
    var isQuickAccess: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String,
        content: String,
        icon: String = "text.badge.plus",
        sortOrder: Int = 0,
        isQuickAccess: Bool = true
    ) {
        self.name = name
        self.content = content
        self.icon = icon
        self.sortOrder = sortOrder
        self.isQuickAccess = isQuickAccess
    }
}
