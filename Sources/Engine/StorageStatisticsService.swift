import Foundation

struct StorageStatisticBucket: Identifiable, Sendable {
    let id: String
    let label: String
    let value: Int
}

struct StorageStatisticsSnapshot: Sendable {
    var totalItems = 0
    var totalBytes: Int64 = 0
    var databaseBytes: Int64 = 0
    var originalsBytes: Int64 = 0
    var oldItemCount = 0
    var typeBuckets: [StorageStatisticBucket] = []
    var appBuckets: [StorageStatisticBucket] = []
    var growthBuckets: [StorageStatisticBucket] = []
}

enum StorageStatisticsService {
    static func load(now: Date = Date()) -> StorageStatisticsSnapshot {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.pastememo"
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return StorageStatisticsSnapshot()
        }
        let directory = appSupport.appendingPathComponent(bundleID)
        let storeURL = directory.appendingPathComponent("PasteMemo.store")
        guard let db = SQLiteConnection(path: storeURL.path, readOnly: true) else {
            let bytes = directorySize(directory)
            return StorageStatisticsSnapshot(totalBytes: bytes, databaseBytes: bytes)
        }
        defer { db.close() }

        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        let typeRows = db.queryStringIntPairs(
            "SELECT COALESCE(ZCONTENTTYPERAW, 'text'), COUNT(*) FROM ZCLIPITEM GROUP BY ZCONTENTTYPERAW ORDER BY COUNT(*) DESC"
        )
        let appRows = db.queryStringIntPairs(
            "SELECT COALESCE(ZSOURCEAPP, ''), COUNT(*) FROM ZCLIPITEM GROUP BY ZSOURCEAPP ORDER BY COUNT(*) DESC LIMIT 8"
        )
        let growthRows = db.queryStringIntPairs(
            """
            SELECT strftime('%Y-%m', ZCREATEDAT + 978307200, 'unixepoch', 'localtime'), COUNT(*)
            FROM ZCLIPITEM
            WHERE ZCREATEDAT >= ?
            GROUP BY 1 ORDER BY 1
            """,
            params: [Calendar.current.date(byAdding: .month, value: -11, to: now)?.timeIntervalSinceReferenceDate ?? 0]
        )
        let originalsURL = directory.appendingPathComponent("Originals")
        let databaseBytes = fileSize(storeURL)
            + fileSize(URL(fileURLWithPath: storeURL.path + "-wal"))
            + fileSize(URL(fileURLWithPath: storeURL.path + "-shm"))
        let originalsBytes = directorySize(originalsURL)

        return StorageStatisticsSnapshot(
            totalItems: db.queryInt("SELECT COUNT(*) FROM ZCLIPITEM"),
            totalBytes: directorySize(directory),
            databaseBytes: databaseBytes,
            originalsBytes: originalsBytes,
            oldItemCount: db.queryInt(
                """
                SELECT COUNT(*) FROM ZCLIPITEM
                WHERE ZCREATEDAT < ? AND ZISPINNED = 0
                  AND (ZGROUPNAME IS NULL OR ZGROUPNAME NOT IN (
                      SELECT ZNAME FROM ZSMARTGROUP WHERE ZPRESERVESITEMS = 1
                  ))
                """,
                params: [cutoff.timeIntervalSinceReferenceDate]
            ),
            typeBuckets: typeRows.map { StorageStatisticBucket(id: $0.0, label: $0.0, value: $0.1) },
            appBuckets: appRows.map { StorageStatisticBucket(id: $0.0.isEmpty ? "__unknown" : $0.0, label: $0.0, value: $0.1) },
            growthBuckets: growthRows.map { StorageStatisticBucket(id: $0.0, label: $0.0, value: $0.1) }
        )
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
