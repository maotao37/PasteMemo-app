import Charts
import SwiftData
import SwiftUI

struct StorageStatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot = StorageStatisticsSnapshot()
    @State private var processMetrics = ProcessMetricsSnapshot()
    @State private var isLoading = true
    @State private var showOldCleanupConfirmation = false
    @State private var isCleaning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 程序运行时系统资源（仅页面打开时实时采集）
                runtimeMetricsSection

                // 存储空间各目录占用明细
                directoryBreakdownSection

                // 增长图表与类型/App 分布
                chartSection
                distributionSection

                // 清理建议
                recommendationsSection
            }
            .padding(22)
        }
        .navigationTitle(L10n.tr("stats.storage.title"))
        .toolbar {
            Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                .help(L10n.tr("stats.refresh"))
                .disabled(isLoading || isCleaning)
        }
        // 仅在页面打开时启动监控，离开页面时自动取消任务
        .task {
            await monitorRuntimeMetrics()
        }
        .alert(L10n.tr("stats.cleanup.old.title"), isPresented: $showOldCleanupConfirmation) {
            Button(L10n.tr("action.delete"), role: .destructive) { cleanOldItems() }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("stats.cleanup.old.confirm", snapshot.oldItemCount))
        }
    }

    // MARK: - 程序实时资源占用（CPU / 内存 / 磁盘占用）

    private var runtimeMetricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.tr("stats.runtime.title")).font(.headline)

                // 实时监测中呼吸指示标签
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(L10n.tr("stats.runtime.monitoring"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12), in: Capsule())

                Spacer()

                Text(L10n.tr("stats.runtime.hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                // CPU 占用
                runtimeCard(
                    title: L10n.tr("stats.runtime.cpu"),
                    value: String(format: "%.1f%%", processMetrics.cpuUsage),
                    subtext: L10n.tr("stats.runtime.cpu.hint"),
                    icon: "cpu",
                    tint: processMetrics.cpuUsage > 40.0 ? PasteMemoVisualStyle.warning : Color.accentColor
                )

                // 物理内存占用 (Footprint)
                runtimeCard(
                    title: L10n.tr("stats.runtime.memory"),
                    value: ByteCountFormatter.string(fromByteCount: processMetrics.memoryBytes, countStyle: .memory),
                    subtext: L10n.tr("stats.runtime.memory.hint"),
                    icon: "memorychip",
                    tint: Color.accentColor
                )

                // 程序磁盘占用
                runtimeCard(
                    title: L10n.tr("stats.runtime.disk"),
                    value: ByteCountFormatter.string(fromByteCount: processMetrics.diskUsageBytes, countStyle: .file),
                    subtext: processMetrics.diskFreeBytes > 0
                        ? L10n.tr("stats.runtime.diskFree", ByteCountFormatter.string(fromByteCount: processMetrics.diskFreeBytes, countStyle: .file))
                        : "",
                    icon: "internaldrive",
                    tint: Color.accentColor
                )
            }
        }
    }

    private func runtimeCard(title: String, value: String, subtext: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if !subtext.isEmpty {
                    Text(subtext)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PasteMemoVisualStyle.subtleStroke))
    }

    // MARK: - 存储目录占用明细

    private var directoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("stats.directory.title")).font(.headline)
                Spacer()
                Text(L10n.tr("stats.storage.total") + "：\(ByteCountFormatter.string(fromByteCount: snapshot.totalBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                if snapshot.directoryItems.isEmpty {
                    Text(L10n.tr("stats.noData"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ForEach(Array(snapshot.directoryItems.enumerated()), id: \.element.id) { index, item in
                        directoryRow(item)
                        if index < snapshot.directoryItems.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PasteMemoVisualStyle.subtleStroke))
        }
    }

    private func directoryRow(_ item: StorageDirectoryItem) -> some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: item.iconName)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            // 名称与路径
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L10n.tr(item.nameKey))
                        .font(.callout.weight(.medium))
                    Text(item.folderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }

                Text(item.displayPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // 占比条
            let ratio = snapshot.totalBytes > 0 ? Double(item.bytes) / Double(snapshot.totalBytes) : 0.0
            VStack(alignment: .trailing, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 5)
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(3, geo.size.width * CGFloat(min(1.0, ratio))), height: 5)
                    }
                }
                .frame(width: 65, height: 5)

                Text(String(format: "%.1f%%", ratio * 100))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            // 大小与文件数
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(L10n.tr("stats.directory.files", item.fileCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 78, alignment: .trailing)

            // 在访达中查看按钮
            Button {
                revealInFinder(path: item.path)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("stats.directory.reveal"))
            .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            if isDir.boolValue {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            } else {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            }
        } else {
            let parent = url.deletingLastPathComponent().path
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parent)
        }
    }

    // MARK: - 剪贴记录增长趋势

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("stats.growth")).font(.headline)
            if snapshot.growthBuckets.isEmpty {
                Text(L10n.tr("stats.noData"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(snapshot.growthBuckets) { bucket in
                    BarMark(x: .value("Month", bucket.label), y: .value("Clips", bucket.value))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(3)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
            }
        }
    }

    // MARK: - 内容类型与来源 App 分布

    private var distributionSection: some View {
        HStack(alignment: .top, spacing: 28) {
            ranking(L10n.tr("stats.byType"), buckets: snapshot.typeBuckets.prefix(8).map {
                StorageStatisticBucket(
                    id: $0.id,
                    label: ClipContentType(rawValue: $0.label)?.label ?? $0.label,
                    value: $0.value
                )
            })
            ranking(L10n.tr("stats.byApp"), buckets: snapshot.appBuckets.map {
                StorageStatisticBucket(
                    id: $0.id,
                    label: $0.label.isEmpty ? L10n.tr("filter.other") : $0.label,
                    value: $0.value
                )
            })
        }
    }

    private func ranking(_ title: String, buckets: [StorageStatisticBucket]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            ForEach(buckets) { bucket in
                HStack {
                    Text(bucket.label).lineLimit(1)
                    Spacer()
                    Text("\(bucket.value)").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.callout)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - 清理建议

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("stats.recommendations")).font(.headline)
            HStack(spacing: 12) {
                Image(systemName: snapshot.oldItemCount > 0 ? "clock.badge.exclamationmark" : "checkmark.circle")
                    .foregroundStyle(snapshot.oldItemCount > 0 ? PasteMemoVisualStyle.warning : PasteMemoVisualStyle.success)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.oldItemCount > 0 ? L10n.tr("stats.cleanup.old.suggestion", snapshot.oldItemCount) : L10n.tr("stats.cleanup.none"))
                    Text(L10n.tr("stats.cleanup.protected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if snapshot.oldItemCount > 0 {
                    Button(L10n.tr("stats.cleanup.action")) { showOldCleanupConfirmation = true }
                        .disabled(isCleaning)
                }
            }
            .padding(12)
            .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 实时监控与数据加载

    /// 页面打开时启动轻量实时监控循环，退出页面时 Task 自动取消并终止
    private func monitorRuntimeMetrics() async {
        // 进入时先触发一次全量数据加载
        reload()

        // 在前台打开期间每 2 秒轻量更新一次当前进程指标
        while !Task.isCancelled {
            let metrics = await Task.detached(priority: .utility) {
                ProcessMetricsService.current()
            }.value

            if Task.isCancelled { break }
            self.processMetrics = metrics

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func reload() {
        isLoading = true
        Task {
            async let storageSnapshot = Task.detached(priority: .utility) {
                StorageStatisticsService.load()
            }.value

            async let metricsSnapshot = Task.detached(priority: .utility) {
                ProcessMetricsService.current()
            }.value

            let (storage, metrics) = await (storageSnapshot, metricsSnapshot)
            self.snapshot = storage
            self.processMetrics = metrics
            self.isLoading = false
        }
    }

    private func cleanOldItems() {
        isCleaning = true
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { !$0.isPinned && $0.createdAt < cutoff })
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let preserved = SmartGroupRetention.preservedGroupNames(in: modelContext)
        let deletable = SmartGroupRetention.filterDeletableItems(fetched, preservedGroupNames: preserved)
        Task { @MainActor in
            await ClipItemStore.deleteAndNotifyBatched(deletable, from: modelContext)
            isCleaning = false
            reload()
        }
    }
}

