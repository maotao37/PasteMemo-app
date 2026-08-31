import Foundation
import Testing
@testable import PasteMemo

@Suite("Smart group filters")
struct SmartGroupFilterTests {
    @Test("empty filter has no conditions")
    func emptyFilter() {
        let filter = SmartGroupFilter()
        var params: [Any] = []
        #expect(!filter.hasConditions)
        #expect(ClipItemStore.smartGroupConditions(filter, params: &params).isEmpty)
        #expect(params.isEmpty)
    }

    @Test("combined filter emits parameterized SQL")
    func combinedFilter() {
        let filter = SmartGroupFilter(
            query: "release notes",
            contentTypeRaw: ClipContentType.text.rawValue,
            sourceApp: "Safari",
            flagRaw: SmartGroupFlag.pinned.rawValue,
            recentDays: 14,
            matchModeRaw: SmartGroupMatchMode.all.rawValue
        )
        var params: [Any] = []
        let conditions = ClipItemStore.smartGroupConditions(
            filter,
            params: &params,
            now: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )

        #expect(filter.hasConditions)
        #expect(conditions.count == 5)
        #expect(conditions.contains { $0.contains("clip_fts") })
        #expect(conditions.contains("ZISPINNED = 1"))
        #expect(params.count == 13)
        #expect(params.contains { ($0 as? String) == "%Safari%" })
    }
}
