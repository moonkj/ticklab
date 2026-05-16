import SwiftData
import SwiftUI
import UIKit

struct JournalEntryDetailView: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroPhoto
                // Round 172: 사진이 2장 이상이면 가로 carousel 표시.
                if entry.photoPaths.count > 1 {
                    photoCarousel
                }
                headerSection
                bodySection
                if let measurementId = entry.measurementId {
                    measurementCard(measurementId: measurementId)
                }
                shareCTA
            }
            .padding(20)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(AppDateFormat.fullDate(entry.timestamp))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sharing = true
                    } label: {
                        Label(String(localized: "journal.detail.share"), systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(AppColors.ink2)
                }
                .accessibilityLabel(String(localized: "a11y.more_actions"))
            }
        }
        .sheet(isPresented: $sharing) {
            let rate: Double? = {
                guard let mid = entry.measurementId else { return nil }
                let desc = FetchDescriptor<WatchMeasurement>(predicate: #Predicate { $0.id == mid })
                return (try? modelContext.fetch(desc))?.first?.rateSecondsPerDay
            }()
            let entryPhotoData: Data? = entry.photoPaths.first.flatMap { stored in
                EXIFStripper.resolvePhotoPath(stored).flatMap { path in
                    try? Data(contentsOf: URL(fileURLWithPath: path))
                }
            }
            ShareCardComposerView(entry: entry, directRate: rate, entryPhotoData: entryPhotoData)
                .presentationDetents([.large])
        }
        .confirmationDialog(
            String(localized: "journal.detail.delete.confirm"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                entry.deleteWithFiles(in: modelContext)
                try? modelContext.save()
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "journal.detail.delete.message"))
        }
    }

    /// Round 67: photoPath empty + watch 있으면 WatchSilhouette 표시 (디자인 SSOT 의 placeholder).
    // Round 170: photoPaths 가 있으면 실제 첫 사진 로드 (이전엔 placeholder 만).
    private var heroPhoto: some View {
        RoundedRectangle(cornerRadius: AppRadius.lg)
            .fill(AppColors.paper2)
            .frame(height: 280)
            .overlay {
                if let stored = entry.photoPaths.first,
                   let firstPath = EXIFStripper.resolvePhotoPath(stored),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: firstPath)),
                   let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else if let watch = entry.watch {
                    WatchSilhouette(watch: watch, size: 180)
                } else {
                    Text(entry.mood.emoji)
                        .font(.system(size: 64))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.mood.emoji)
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 2) {
                if let watch = entry.watch {
                    Text(watch.brand.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(AppColors.ink2)
                    Text(watch.model)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(AppColors.ink0)
                }
                Text(AppDateFormat.monthDayTime(entry.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
            }
            Spacer()
        }
    }

    /// Round 172: 첫 사진은 hero, 나머지는 가로 carousel.
    private var photoCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(entry.photoPaths.dropFirst().enumerated()), id: \.offset) { _, stored in
                    if let path = EXIFStripper.resolvePhotoPath(stored),
                       let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var bodySection: some View {
        Text(entry.body.isEmpty ? String(localized: "journal.detail.no_body") : entry.body)
            .font(.system(size: 15, design: .serif))
            .foregroundStyle(entry.body.isEmpty ? AppColors.ink3 : AppColors.ink0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    /// Round 143: 실 WatchMeasurement fetch + rate / beat error / confidence 표시.
    private func measurementCard(measurementId: UUID) -> some View {
        let measurement = try? modelContext.fetch(
            FetchDescriptor<WatchMeasurement>(predicate: #Predicate { $0.id == measurementId })
        ).first
        return VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "journal.detail.measurement_attached"), systemImage: "waveform.path.ecg")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(AppColors.accent)
            if let m = measurement {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Round 125 (Hard Rule 3): "RATE", "s/d" → localize.
                        Text(String(localized: "watch.label.rate"))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(AppColors.ink2)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text((m.rateSecondsPerDay >= 0 ? "+" : "") + String(format: "%.1f", m.rateSecondsPerDay))
                                .font(.system(size: 22, design: .monospaced))
                                .foregroundStyle(AppColors.ink0)
                            Text(String(localized: "unit.seconds_per_day_short"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppColors.ink2)
                        }
                    }
                    Spacer()
                    ConfidenceBadge(score: m.confidenceScore, compact: true)
                }
                HStack(spacing: 14) {
                    Text(String(format: String(localized: "journal.detail.beat_error"), m.beatErrorMs))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                    if let amp = m.amplitudeDegrees {
                        Text("\(Int(amp))°")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppColors.ink2)
                    }
                }
            } else {
                Text(String(localized: "journal.detail.measurement_deleted"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accent50)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var shareCTA: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            sharing = true
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up.fill")
                Text(String(localized: "journal.detail.share_card_cta"))
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .foregroundStyle(AppColors.paper0)
            .background(AppColors.primaryDeep)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}
