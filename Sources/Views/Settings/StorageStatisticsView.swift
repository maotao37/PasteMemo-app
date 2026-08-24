import Charts
import SwiftData
import SwiftUI

struct StorageStatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot = StorageStatisticsSnapshot()
    @State private var isLoading = true
    @State private var showOldCleanupConfirmation = false
    @State private var isCleaning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryStrip
                chartSection
                distributionSection
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
        .onAppear { reload() }
        .alert(L10n.tr("stats.cleanup.old.title"), isPresented: $showOldCleanupConfirmation) {
            Button(L10n.tr("action.delete"), role: .destructive) { cleanOldItems() }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("stats.cleanup.old.confirm", snapshot.oldItemCount))
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 1) {
            metric(L10n.tr("stats.total"), value: "\(snapshot.totalItems)", icon: "doc.on.clipboard")
            Divider()
            metric(L10n.tr("stats.storage.total"), value: ByteCountFormatter.string(fromByteCount: snapshot.totalBytes, countStyle: .file), icon: "internaldrive")
            Divider()
            metric(L10n.tr("stats.storage.originals"), value: ByteCountFormatter.string(fromByteCount: snapshot.originalsBytes, countStyle: .file), icon: "photo.stack")
        }
        .frame(height: 82)
        .background(PasteMemoVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PasteMemoVisualStyle.subtleStroke))
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

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

    private func reload() {
        isLoading = true
        Task {
            let value = await Task.detached(priority: .utility) { StorageStatisticsService.load() }.value
            snapshot = value
            isLoading = false
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
