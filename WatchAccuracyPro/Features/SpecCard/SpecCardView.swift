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
    @Environment(UserPreferences.self) private var preferences
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    /// Round 174: SpecCard 삭제 확인 alert.
    @State private var deleteAlert: Bool = false
    /// AI 모델 설명/착장 의견.
    @State private var aiText: String?
    @State private var aiLoading = false

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
            aiSection
        }
        .padding(20)
    }

    /// 사용자 요청: 스펙카드 하단 AI 모델 설명 + 착장 의견 (Apple Intelligence, 없으면 rule 폴백).
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.accentDark)
                Text(String(localized: "speccard.ai.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                // 다시 생성 — 캐시된 해설이 시계와 안 맞을 때 갱신.
                if (aiText ?? card.aiDescription) != nil, !aiLoading {
                    Button { Task { await regenerateAIDescription() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "common.refresh"))
                }
            }
            if let text = aiText ?? card.aiDescription {
                Text(text)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(AppColors.ink0)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if aiLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(String(localized: "speccard.ai.loading"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accent50)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.accentLight, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .task { await loadAIDescription() }
    }

    private func loadAIDescription() async {
        // 캐시 있으면 재사용(매번 LLM 호출 방지).
        if let cached = card.aiDescription, !cached.isEmpty { aiText = cached; return }
        guard let watch = card.watch else { return }
        aiLoading = true
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        // 스펙 요약(주어진 수치만) — AI가 이것만 grounding 해설하도록(할루시네이션 방지).
        var parts: [String] = []
        if !card.movement.isEmpty { parts.append(card.movement) }
        if let cs = card.caseSize { parts.append(String(format: "%.1f mm", cs)) }
        if let pr = card.powerReserveHours { parts.append(String(format: "%.0f h", pr)) }
        if let la = card.liftAngle { parts.append(String(format: "lift %.0f°", la)) }
        let specSummary = parts.joined(separator: " · ")
        let text = await WatchDescriptionService.shared.describe(
            brand: watch.brand, model: watch.model, caliber: watch.caliber,
            specSummary: specSummary, movement: watch.movementType,
            aiEnabled: preferences.aiVerdictEnabled, languageCode: lang
        )
        card.aiDescription = text
        try? modelContext.save()
        aiText = text
        aiLoading = false
    }

    /// 캐시된 해설 폐기 후 현재 스펙으로 재생성 — "시계와 안 맞을 때" 사용자 갱신.
    private func regenerateAIDescription() async {
        card.aiDescription = nil
        aiText = nil
        try? modelContext.save()
        await loadAIDescription()
    }

    private var specTable: some View {
        VStack(spacing: 0) {
            specRow(String(localized: "speccard.spec.movement"), card.movement)
            specRow(String(localized: "speccard.spec.case"), card.caseSize.map { String(format: "%.1f mm", $0) })
            specRow(String(localized: "speccard.spec.power_reserve"), card.powerReserveHours.map { String(format: "%.0f h", $0) })
            specRow(String(localized: "speccard.spec.registered"), AppDateFormat.fullDate(card.createdAt))
        }
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
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
                Image(systemName: "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.ink2)
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
