import AVFoundation
import SwiftData
import SwiftUI
import UIKit

/// 저장된 SpecCard 표시 — 카탈로그 카드 스타일.
/// 사진 hero + 시계 메타 + spec table + 사운드 재생 + 공유.
struct SpecCardView: View {
    @Bindable var card: SpecCard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    /// Round 174: SpecCard 삭제 확인 alert.
    @State private var deleteAlert: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    contentCard
                }
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        deleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(String(localized: "common.delete"))
                }
            }
            .alert(
                String(localized: "speccard.delete.title"),
                isPresented: $deleteAlert
            ) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "common.delete"), role: .destructive) {
                    let fm = FileManager.default
                    if let p = card.audioPath, fm.fileExists(atPath: p) {
                        try? fm.removeItem(atPath: p)
                    }
                    if let p = card.photoPath, fm.fileExists(atPath: p) {
                        try? fm.removeItem(atPath: p)
                    }
                    modelContext.delete(card)
                    try? modelContext.save()
                    dismiss()
                }
            } message: {
                Text(String(localized: "speccard.delete.body"))
            }
        }
    }

    private var hero: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.primaryDeep, AppColors.primary700],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let pp = card.photoPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: pp)),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let watch = card.watch {
                if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    WatchSilhouette(watch: watch, size: 200)
                }
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .center, endPoint: .bottom
            )
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.watch?.brand.uppercased() ?? "")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(2.5)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(card.title)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(20)
            }
        }
        .frame(height: 320)
    }

    private var contentCard: some View {
        VStack(spacing: 16) {
            specTable
            if card.audioPath != nil {
                soundButton
            }
            if !card.note.isEmpty {
                noteSection
            }
        }
        .padding(20)
    }

    /// 캘리버 → 무브먼트 DB 매칭(수동입력 sentinel 제외).
    private var dbMovement: Movement? {
        card.watch?.caliber.flatMap {
            $0 == Watch.manualCaliberTag ? nil : MovementDatabase.shared.movement(id: $0)
        }
    }

    /// 팀 토론 기획: 빈 행 숨김 + 시계(card.watch)에서 스펙 풍부화(구동방식·캘리버·BPH·레퍼런스·측정통계).
    private var specTable: some View {
        VStack(spacing: 0) {
            // 시계 기본 스펙 — 거의 항상 채워짐.
            if let w = card.watch {
                specRow(String(localized: "speccard.spec.movement_type", defaultValue: "구동 방식"), w.movementType.displayName)
                if let cal = w.caliber, !cal.isEmpty, !w.isCaliberManualEntry {
                    specRow(String(localized: "speccard.spec.caliber", defaultValue: "캘리버"), cal)
                }
            }
            // 사용자 입력 (있는 것만).
            if !card.movement.isEmpty {
                specRow(String(localized: "speccard.spec.movement"), card.movement)
            }
            if let cs = card.caseSize {
                specRow(String(localized: "speccard.spec.case"), String(format: "%.1f mm", cs))
            }
            if let ct = card.caseThickness {
                specRow(String(localized: "speccard.field.case_thickness"), String(format: "%.1f mm", ct))
            }
            if let ll = card.lugToLug {
                specRow(String(localized: "speccard.field.lug_to_lug"), String(format: "%.1f mm", ll))
            }
            if let wr = card.waterResistanceM {
                specRow(String(localized: "speccard.field.water_resistance"), "\(wr) m")
            }
            if let mat = card.caseMaterial, !mat.isEmpty {
                specRow(String(localized: "speccard.field.material"), mat)
            }
            if let dc = card.dialColor, !dc.isEmpty {
                specRow(String(localized: "speccard.field.dial_color"), dc)
            }
            if let cr = card.crystal, !cr.isEmpty {
                specRow(String(localized: "speccard.field.crystal"), cr)
            }
            if let pr = card.powerReserveHours {
                specRow(String(localized: "speccard.spec.power_reserve"), String(format: "%.0f h", pr))
            }
            // 진동수 — DB / 직접입력 / 측정값 순.
            if let bph = bphValue {
                specRow(String(localized: "speccard.spec.bph"), "\(bph)")
            }
            if let m = dbMovement {
                specRow(String(localized: "speccard.spec.lift_angle"), "\(Int(m.liftAngleDegrees.rounded()))°")
            }
            if let w = card.watch {
                if let ref = w.referenceNumber, !ref.isEmpty {
                    specRow(String(localized: "speccard.spec.reference", defaultValue: "레퍼런스"), ref)
                }
                if let py = w.productionYear {
                    specRow(String(localized: "speccard.spec.production_year", defaultValue: "생산 연도"), "\(py)")
                }
            }
            // 측정 통계 — 내 개체 실측(신뢰도 25+).
            if measureCount > 0 {
                specRow(String(localized: "speccard.spec.measure_count", defaultValue: "측정 횟수"), "\(measureCount)")
            }
            if let best = bestRate {
                specRow(String(localized: "speccard.spec.best_rate", defaultValue: "최고 정확도"),
                        String(format: "±%.1f s/d", best))
            }
            if let avg = avgMeasuredRate {
                specRow(String(localized: "speccard.spec.measured_rate"),
                        String(format: "%@%.1f s/d", avg >= 0 ? "+" : "", avg))
            }
            // 진폭 — Hard Rule #9: high/veryHigh 신뢰 무브먼트만(DB 매칭 + 표시 가능 등급).
            if dbMovement?.shouldDisplayAmplitude == true, let amp = avgAmplitude {
                specRow(String(localized: "speccard.spec.amplitude", defaultValue: "평균 진폭"),
                        String(format: "%.0f°", amp))
            }
            if let be = avgBeatError {
                specRow(String(localized: "speccard.spec.beat_error", defaultValue: "평균 비트에러"),
                        String(format: "%.1f ms", be))
            }
            specRow(String(localized: "speccard.spec.registered"), AppDateFormat.fullDate(card.createdAt))
        }
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    // MARK: - 측정 통계 (신뢰도 25+ 만)
    private var validMeasurements: [WatchMeasurement] {
        (card.watch?.measurements ?? []).filter { $0.confidenceScore >= 25 }
    }
    private var measureCount: Int { card.watch?.measurements.count ?? 0 }
    /// 내 개체 실측 평균 rate.
    private var avgMeasuredRate: Double? {
        guard !validMeasurements.isEmpty else { return nil }
        return validMeasurements.map(\.rateSecondsPerDay).reduce(0, +) / Double(validMeasurements.count)
    }
    /// 최고 정확도 — |rate| 최소.
    private var bestRate: Double? {
        validMeasurements.map { abs($0.rateSecondsPerDay) }.min()
    }
    private var avgAmplitude: Double? {
        let amps = validMeasurements.compactMap(\.amplitudeDegrees)
        guard !amps.isEmpty else { return nil }
        return amps.reduce(0, +) / Double(amps.count)
    }
    private var avgBeatError: Double? {
        guard !validMeasurements.isEmpty else { return nil }
        return validMeasurements.map(\.beatErrorMs).reduce(0, +) / Double(validMeasurements.count)
    }
    /// 진동수 — DB → 직접입력 → 측정값(최빈/최댓값) 순.
    private var bphValue: Int? {
        if let m = dbMovement { return m.bph }
        if let c = card.watch?.customBph, c > 0 { return c }
        let bphs = (card.watch?.measurements ?? []).map(\.bph).filter { $0 > 0 }
        return bphs.max()
    }

    private func specRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(AppColors.ink2)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(AppColors.ink0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColors.rule).frame(height: 1)
        }
    }

    private var soundButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            playPause()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColors.accent)
                Text(String(localized: isPlaying ? "speccard.play.label.playing" : "speccard.play.label.idle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Spacer()
                ConceptGlyph(systemName: "waveform", size: 20, color: AppColors.ink2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColors.accent50)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.accentLight, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "speccard.play.a11y"))
        .accessibilityValue(String(localized: isPlaying ? "speccard.play.label.playing" : "speccard.play.label.idle"))
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "speccard.note"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.ink2)
            Text(card.note)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.ink0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppColors.paper1)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
    }

    @State private var playerDelegate: PlayerDelegate?

    private func playPause() {
        guard let path = card.audioPath else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int,
              size > 0 else { return }
        if let p = player, p.isPlaying {
            p.pause()
            isPlaying = false
            return
        }
        do {
            // Round 154: .playback 카테고리 — record 세션 없이 안정적으로 speaker.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            playerDelegate = PlayerDelegate { isPlaying = false }
            p.delegate = playerDelegate
            p.volume = 1.0
            guard p.prepareToPlay() else { return }
            player = p
            if p.play() { isPlaying = true }
        } catch {
            // ignore
        }
    }

    private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }
    }
}
