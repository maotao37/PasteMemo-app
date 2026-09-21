import Foundation

struct StorageStatisticBucket: Identifiable, Sendable {
    let id: String
    let label: String
    let value: Int
}

/// 单个存储目录或文件的占用明细
struct StorageDirectoryItem: Identifiable, Sendable {
    let id: String
    /// 本地化键名或友好名称
    let nameKey: String
    /// 默认名称
    let defaultName: String
    /// 目录名或文件名（如：Originals、PasteMemo.store、Caches 等）
    let folderName: String
    /// 完整绝对路径
    let path: String
    /// 紧凑友好的展示路径（以 ~/ 开头）
    let displayPath: String
    /// 占用的存储大小（字节）
    let bytes: Int64
    /// 包含的文件数量
    let fileCount: Int
    /// 对应的 SF Symbol 图标名称
    let iconName: String
    /// 是否为目录
    let isDirectory: Bool
    /// 文件系统 URL，便于在访达中定位
    let fileURL: URL
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
    /// 各个目录和关键存储模块的明细
    var directoryItems: [StorageDirectoryItem] = []
}

enum StorageStatisticsService {
    static func load(now: Date = Date()) -> StorageStatisticsSnapshot {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.pastememo"
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return StorageStatisticsSnapshot()
        }
        let directory = appSupport.appendingPathComponent(bundleID)
        let storeURL = directory.appendingPathComponent("PasteMemo.store")

        // 收集各目录占用明细
        let directoryItems = inspectDirectories(appSupportDir: directory, bundleID: bundleID)
        let totalCalculatedBytes = directoryItems.reduce(0) { $0 + $1.bytes }

        guard let db = SQLiteConnection(path: storeURL.path, readOnly: true) else {
            let bytes = max(directorySize(directory), totalCalculatedBytes)
            return StorageStatisticsSnapshot(
                totalBytes: bytes,
                databaseBytes: fileSize(storeURL),
                directoryItems: directoryItems
            )
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
            totalBytes: max(directorySize(directory), totalCalculatedBytes),
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
            growthBuckets: growthRows.map { StorageStatisticBucket(id: $0.0, label: $0.0, value: $0.1) },
            directoryItems: directoryItems
        )
    }

    /// 深度扫描应用所涉及的各个存储目录与文件
    private static func inspectDirectories(appSupportDir: URL, bundleID: String) -> [StorageDirectoryItem] {
        var items: [StorageDirectoryItem] = []
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser

        // 路径友好化转换（将 /Users/xxx 替换为 ~）
        func makeDisplayPath(_ url: URL) -> String {
            let path = url.path
            let homePath = homeDir.path
            if path.hasPrefix(homePath) {
                return "~" + path.dropFirst(homePath.count)
            }
            return path
        }

        // 1. 数据库与索引文件 (PasteMemo.store, -wal, -shm)
        let storeURL = appSupportDir.appendingPathComponent("PasteMemo.store")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let dbBytes = fileSize(storeURL) + fileSize(walURL) + fileSize(shmURL)
        var dbFileCount = 0
        if fileManager.fileExists(atPath: storeURL.path) { dbFileCount += 1 }
        if fileManager.fileExists(atPath: walURL.path) { dbFileCount += 1 }
        if fileManager.fileExists(atPath: shmURL.path) { dbFileCount += 1 }

        if dbBytes > 0 || dbFileCount > 0 {
            items.append(StorageDirectoryItem(
                id: "database",
                nameKey: "stats.directory.database",
                defaultName: "数据库与索引",
                folderName: "PasteMemo.store",
                path: storeURL.path,
                displayPath: makeDisplayPath(storeURL),
                bytes: dbBytes,
                fileCount: dbFileCount,
                iconName: "cylinder.split.1x2",
                isDirectory: false,
                fileURL: storeURL
            ))
        }

        // 2. 原始图片目录 (Originals)
        let originalsURL = appSupportDir.appendingPathComponent("Originals")
        if fileManager.fileExists(atPath: originalsURL.path) {
            let (bytes, count) = measureDirectory(originalsURL)
            items.append(StorageDirectoryItem(
                id: "originals",
                nameKey: "stats.directory.originals",
                defaultName: "原始图片",
                folderName: "Originals",
                path: originalsURL.path,
                displayPath: makeDisplayPath(originalsURL),
                bytes: bytes,
                fileCount: count,
                iconName: "photo.stack",
                isDirectory: true,
                fileURL: originalsURL
            ))
        }

        // 3. 自动与本地备份目录 (backups)
        let backupsURL = appSupportDir.appendingPathComponent("backups")
        if fileManager.fileExists(atPath: backupsURL.path) {
            let (bytes, count) = measureDirectory(backupsURL)
            if bytes > 0 || count > 0 {
                items.append(StorageDirectoryItem(
                    id: "backups",
                    nameKey: "stats.directory.backups",
                    defaultName: "本地备份",
                    folderName: "backups",
                    path: backupsURL.path,
                    displayPath: makeDisplayPath(backupsURL),
                    bytes: bytes,
                    fileCount: count,
                    iconName: "archivebox",
                    isDirectory: true,
                    fileURL: backupsURL
                ))
            }
        }

        // 4. Application Support 目录下的其他条目（动态扫描）
        if let subItems = try? fileManager.contentsOfDirectory(at: appSupportDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for subURL in subItems {
                let name = subURL.lastPathComponent
                // 跳过已知的主项
                if name == "Originals" || name == "backups" || name.hasPrefix("PasteMemo.store") {
                    continue
                }
                let isDir = (try? subURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let (bytes, count) = isDir ? measureDirectory(subURL) : (fileSize(subURL), 1)
                guard bytes > 0 else { continue }
                items.append(StorageDirectoryItem(
                    id: "appSupport_\(name)",
                    nameKey: "stats.directory.other",
                    defaultName: name,
                    folderName: name,
                    path: subURL.path,
                    displayPath: makeDisplayPath(subURL),
                    bytes: bytes,
                    fileCount: count,
                    iconName: isDir ? "folder" : "doc",
                    isDirectory: isDir,
                    fileURL: subURL
                ))
            }
        }

        // 5. 系统缓存目录 (Caches)
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let cacheDir = caches.appendingPathComponent(bundleID)
            if fileManager.fileExists(atPath: cacheDir.path) {
                let (bytes, count) = measureDirectory(cacheDir)
                if bytes > 0 {
                    items.append(StorageDirectoryItem(
                        id: "caches",
                        nameKey: "stats.directory.caches",
                        defaultName: "应用缓存",
                        folderName: "Caches",
                        path: cacheDir.path,
                        displayPath: makeDisplayPath(cacheDir),
                        bytes: bytes,
                        fileCount: count,
                        iconName: "sparkles.rectangle.stack",
                        isDirectory: true,
                        fileURL: cacheDir
                    ))
                }
            }
        }

        // 6. 运行日志目录 (Logs)
        let logsDir = homeDir.appendingPathComponent("Library/Logs/\(bundleID)")
        if fileManager.fileExists(atPath: logsDir.path) {
            let (bytes, count) = measureDirectory(logsDir)
            if bytes > 0 {
                items.append(StorageDirectoryItem(
                    id: "logs",
                    nameKey: "stats.directory.logs",
                    defaultName: "诊断日志",
                    folderName: "Logs",
                    path: logsDir.path,
                    displayPath: makeDisplayPath(logsDir),
                    bytes: bytes,
                    fileCount: count,
                    iconName: "doc.plaintext",
                    isDirectory: true,
                    fileURL: logsDir
                ))
            }
        }

        // 7. 临时工作目录 (Temporary)
        let tempDir = fileManager.temporaryDirectory
        if let tempSubItems = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            var tempBytes: Int64 = 0
            var tempCount = 0
            for item in tempSubItems where item.lastPathComponent.hasPrefix("PasteMemo") {
                let (bytes, count) = measureDirectory(item)
                tempBytes += bytes
                tempCount += count
            }
            if tempBytes > 0 {
                items.append(StorageDirectoryItem(
                    id: "temp",
                    nameKey: "stats.directory.temporary",
                    defaultName: "临时文件",
                    folderName: "PasteMemo-Temp",
                    path: tempDir.path,
                    displayPath: "Temporary/PasteMemo-*",
                    bytes: tempBytes,
                    fileCount: tempCount,
                    iconName: "clock.arrow.circlepath",
                    isDirectory: true,
                    fileURL: tempDir
                ))
            }
        }

        // 按占用大小降序排序
        return items.sorted(by: { $0.bytes > $1.bytes })
    }

    /// 测量指定目录的占用大小与文件数
    private static func measureDirectory(_ url: URL) -> (bytes: Int64, fileCount: Int) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue {
            let size = fileSize(url)
            return (size, size > 0 ? 1 : 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: []
        ) else { return (0, 0) }

        var total: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            count += 1
        }
        return (total, count)
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        return measureDirectory(url).bytes
    }
}
