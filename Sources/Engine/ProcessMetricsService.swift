//
//  ProcessMetricsService.swift
//  PasteMemo
//
//  Created by mao.tao on 2026/09/21.
//

import Foundation
import Darwin
import MachO

/// 进程运行时资源快照
public struct ProcessMetricsSnapshot: Sendable {
    /// 当前进程 CPU 占用率（百分比，例如 1.5 表示 1.5%）
    public var cpuUsage: Double = 0.0
    /// 物理内存占用（字节数，与活动监视器中物理内存占用一致）
    public var memoryBytes: Int64 = 0
    /// 应用程序在磁盘上的总占用（字节数，包含程序包、数据、缓存与日志）
    public var diskUsageBytes: Int64 = 0
    /// 磁盘剩余可用容量（字节数）
    public var diskFreeBytes: Int64 = 0
    /// 磁盘总容量（字节数）
    public var diskTotalBytes: Int64 = 0
    /// 数据采样时间戳
    public var timestamp: Date = Date()

    public init(
        cpuUsage: Double = 0.0,
        memoryBytes: Int64 = 0,
        diskUsageBytes: Int64 = 0,
        diskFreeBytes: Int64 = 0,
        diskTotalBytes: Int64 = 0,
        timestamp: Date = Date()
    ) {
        self.cpuUsage = cpuUsage
        self.memoryBytes = memoryBytes
        self.diskUsageBytes = diskUsageBytes
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.timestamp = timestamp
    }
}

/// 进程资源采样服务，提供当前进程的 CPU、内存、磁盘占用等指标
public enum ProcessMetricsService {
    /// 获取当前进程各项资源指标的实时快照
    public static func current() -> ProcessMetricsSnapshot {
        let cpu = fetchCPUUsage()
        let memory = fetchMemoryUsage()
        let disk = fetchDiskUsage()

        return ProcessMetricsSnapshot(
            cpuUsage: cpu,
            memoryBytes: memory,
            diskUsageBytes: disk.appBytes,
            diskFreeBytes: disk.freeBytes,
            diskTotalBytes: disk.totalBytes,
            timestamp: Date()
        )
    }

    /// 获取当前进程 CPU 占用率（通过遍历所有线程的 Mach task 信息计算）
    public static func fetchCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let threads = threadList else { return 0.0 }
        defer {
            let size = vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size))
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), size)
        }

        var totalUsage: Double = 0.0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let threadKr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if threadKr == KERN_SUCCESS {
                if (info.flags & TH_FLAGS_IDLE) == 0 {
                    totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
        }
        return max(0.0, totalUsage)
    }

    /// 获取物理内存占用（字节数，优先使用 task_vm_info.phys_footprint）
    public static func fetchMemoryUsage() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            return Int64(info.phys_footprint)
        }

        var basicInfo = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let basicKr = withUnsafeMutablePointer(to: &basicInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }
        if basicKr == KERN_SUCCESS {
            return Int64(basicInfo.resident_size)
        }
        return 0
    }

    /// 获取磁盘相关指标（程序磁盘总占用、系统磁盘剩余空间及总空间）
    public static func fetchDiskUsage() -> (appBytes: Int64, freeBytes: Int64, totalBytes: Int64) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.pastememo"
        var appBytes: Int64 = 0

        // 1. Application Support 数据目录占用
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent(bundleID)
            appBytes += directoryOrFileSize(appDir)
        }

        // 2. Caches 缓存目录占用
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let cacheDir = caches.appendingPathComponent(bundleID)
            appBytes += directoryOrFileSize(cacheDir)
        }

        // 3. 日志目录占用
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logsDir = home.appendingPathComponent("Library/Logs/\(bundleID)")
        appBytes += directoryOrFileSize(logsDir)

        // 4. 应用程序 Bundle 本身占用
        let bundleURL = Bundle.main.bundleURL
        appBytes += directoryOrFileSize(bundleURL)

        // 5. 磁盘总空间与可用空间
        var freeBytes: Int64 = 0
        var totalBytes: Int64 = 0
        if let rootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            if let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
                freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
                totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            }
        }

        return (appBytes, freeBytes, totalBytes)
    }

    /// 统计目录或文件的真实磁盘占用大小
    private static func directoryOrFileSize(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
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
