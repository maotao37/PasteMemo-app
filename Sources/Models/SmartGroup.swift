import Foundation
import SwiftData

enum PinboardLayout: String, CaseIterable, Codable {
    case list
    case compact
    case grid

    @MainActor
    var title: String { L10n.tr("group.layout.\(rawValue)") }

    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .compact: "list.bullet.rectangle"
        case .grid: "square.grid.2x2"
        }
    }
}

enum SmartGroupMatchMode: String, CaseIterable, Codable {
    case all
    case any
}

enum SmartGroupFlag: String, CaseIterable, Codable {
    case any
    case pinned
    case favorite
    case sensitive
}

/// Immutable query value used by both the main window and quick panel.
/// Smart groups stay dynamic: matching clips are never assigned a group name.
struct SmartGroupFilter: Equatable, Codable {
    var query = ""
    var contentTypeRaw: String?
    var sourceApp = ""
    var flagRaw = SmartGroupFlag.any.rawValue
    var recentDays = 0
    var matchModeRaw = SmartGroupMatchMode.all.rawValue

    var hasConditions: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || contentTypeRaw != nil
            || !sourceApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || flagRaw != SmartGroupFlag.any.rawValue
            || recentDays > 0
    }

    var matchMode: SmartGroupMatchMode {
        SmartGroupMatchMode(rawValue: matchModeRaw) ?? .all
    }

    var flag: SmartGroupFlag {
        SmartGroupFlag(rawValue: flagRaw) ?? .any
    }
}

@Model
final class SmartGroup {
    var name: String = ""
    var icon: String = "folder"
    var count: Int = 0
    var sortOrder: Int = 0
    var color: String?
    var preservesItems: Bool = false
    /// `manual` groups contain explicitly assigned clips; `smart` groups are live queries.
    var kindRaw: String = "manual"
    var layoutRaw: String = PinboardLayout.list.rawValue
    var isQuickAccess: Bool = false
    var smartQuery: String = ""
    var smartContentTypeRaw: String?
    var smartSourceApp: String = ""
    var smartFlagRaw: String = SmartGroupFlag.any.rawValue
    var smartRecentDays: Int = 0
    var smartMatchModeRaw: String = SmartGroupMatchMode.all.rawValue

    init(
        name: String,
        icon: String = "folder",
        sortOrder: Int = 0,
        color: String? = nil,
        preservesItems: Bool = false,
        kindRaw: String = "manual",
        layoutRaw: String = PinboardLayout.list.rawValue,
        isQuickAccess: Bool = false,
        smartQuery: String = "",
        smartContentTypeRaw: String? = nil,
        smartSourceApp: String = "",
        smartFlagRaw: String = SmartGroupFlag.any.rawValue,
        smartRecentDays: Int = 0,
        smartMatchModeRaw: String = SmartGroupMatchMode.all.rawValue
    ) {
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.color = color
        self.preservesItems = preservesItems
        self.kindRaw = kindRaw
        self.layoutRaw = layoutRaw
        self.isQuickAccess = isQuickAccess
        self.smartQuery = smartQuery
        self.smartContentTypeRaw = smartContentTypeRaw
        self.smartSourceApp = smartSourceApp
        self.smartFlagRaw = smartFlagRaw
        self.smartRecentDays = smartRecentDays
        self.smartMatchModeRaw = smartMatchModeRaw
    }

    var isSmart: Bool { kindRaw == "smart" }

    var layout: PinboardLayout {
        get { PinboardLayout(rawValue: layoutRaw) ?? .list }
        set { layoutRaw = newValue.rawValue }
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

    static let availableColors: [String] = [
        "#0A84FF", "#30D158", "#FFD60A", "#FF9F0A",
        "#FF453A", "#BF5AF2", "#64D2FF", "#8E8E93",
    ]

    static let availableIcons: [String] = [
        // 文件与容器
        "folder", "folder.fill", "tray", "tray.full",
        "archivebox", "doc", "doc.text", "note.text",
        // 标记与收藏
        "bookmark", "tag", "star", "heart",
        "flag", "pin", "rosette", "seal",
        // 工作与生活
        "briefcase", "house", "building.2", "storefront",
        "graduationcap", "person", "person.2", "figure.walk",
        // 网络与通信
        "globe", "link", "envelope", "phone",
        "bubble.left", "antenna.radiowaves.left.and.right", "wifi", "network",
        // 创意与媒体
        "camera", "photo", "music.note", "film",
        "paintbrush", "pencil", "highlighter", "theatermasks",
        // 工具与设置
        "wrench", "gear", "hammer", "slider.horizontal.3",
        "terminal", "chevron.left.forwardslash.chevron.right", "cpu", "memorychip",
        // 自然与天气
        "leaf", "flame", "drop", "bolt",
        "sun.max", "moon", "cloud", "snowflake",
        // 购物与财务
        "cart", "creditcard", "gift", "bag",
        "dollarsign.circle", "banknote", "chart.bar", "chart.pie",
        // 交通与旅行
        "airplane", "car", "bicycle", "map",
        "location", "compass.drawing", "binoculars", "suitcase",
        // 娱乐与运动
        "gamecontroller", "sportscourt", "trophy", "medal",
        "puzzlepiece", "dice", "headphones", "guitars",
        // 健康与安全
        "heart.text.square", "cross.case", "shield", "lock",
        "key", "hand.raised", "eye", "faceid",
        // 食物与饮品
        "cup.and.saucer", "fork.knife", "birthday.cake", "wineglass",
    ]
}
