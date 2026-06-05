import SwiftUI
import UIKit

struct GlossaryView: View {
    /// Round 85/101: 디자인 SSOT screens-detail.jsx GlossaryView — search field + card style entries.
    @State private var query: String = ""

    private let entries: [(key: String, descKey: String, icon: String)] = [
        ("glossary.bph", "glossary.bph.desc", "metronome"),
        ("glossary.rate", "glossary.rate.desc", "speedometer"),
        ("glossary.beat_error", "glossary.beat_error.desc", "waveform"),
        ("glossary.amplitude", "glossary.amplitude.desc", "wave.3.right"),
        ("glossary.cosc", "glossary.cosc.desc", "checkmark.seal"),
        ("glossary.lift_angle", "glossary.lift_angle.desc", "angle"),
        ("glossary.coaxial", "glossary.coaxial.desc", "gearshape.2"),
        ("glossary.mic", "glossary.mic.desc", "mic"),
        ("glossary.onsets", "glossary.onsets.desc", "dot.radiowaves.left.and.right"),
        // Round 121 (이형준 #11): 자주 나오는데 Glossary 에 없는 단어들.
        ("glossary.confidence", "glossary.confidence.desc", "chart.bar.fill"),
        ("glossary.snr", "glossary.snr.desc", "speaker.wave.3"),
        ("glossary.drift", "glossary.drift.desc", "arrow.left.and.right"),
        ("glossary.isochronism", "glossary.isochronism.desc", "clock.arrow.2.circlepath"),
        ("glossary.positional", "glossary.positional.desc", "rotate.3d"),
        // 사용자 요청: 자주 등장하지만 미수록 — power reserve / overhaul / magnetism / escapement.
        ("glossary.power_reserve", "glossary.power_reserve.desc", "battery.75"),
        ("glossary.overhaul", "glossary.overhaul.desc", "wrench.and.screwdriver"),
        ("glossary.magnetism", "glossary.magnetism.desc", "bolt.fill"),
        ("glossary.escapement", "glossary.escapement.desc", "gearshape"),
    ]

    private var filtered: [(key: String, descKey: String, icon: String)] {
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            let title = String(localized: String.LocalizationValue(entry.key)).lowercased()
            let desc = String(localized: String.LocalizationValue(entry.descKey)).lowercased()
            let q = query.lowercased()
            return title.contains(q) || desc.contains(q)
        }
    }

    @State private var selectedEntry: (key: String, descKey: String, icon: String)?

    var body: some View {
        ScrollView {
            // Sprint 8 (UX): 2열 그리드로 컴팩트하게 표시 — 탭 시 바텀 시트 상세
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if filtered.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .gridCellColumns(2)
                        .padding(.top, 32)
                }
                ForEach(filtered, id: \.key) { entry in
                    Button {
                        selectedEntry = entry
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ConceptGlyph(systemName: entry.icon, size: 20, color: AppColors.accent)
                            Text(String(localized: String.LocalizationValue(entry.key)))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.ink0)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(String(localized: String.LocalizationValue(entry.descKey)))
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.ink2)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .background(AppColors.paper1)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .searchable(text: $query, prompt: String(localized: "glossary.search.prompt"))
        .navigationTitle(String(localized: "glossary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { selectedEntry.map { GlossaryEntryID(key: $0.key, descKey: $0.descKey, icon: $0.icon) } },
            set: { if $0 == nil { selectedEntry = nil } }
        )) { item in
            GlossaryDetailSheet(key: item.key, descKey: item.descKey, icon: item.icon)
        }
    }
}

struct GlossaryEntryID: Identifiable {
    // Round 174 (사용자 보고): UUID 면 .sheet(item:) Binding 의 get 이 매 렌더 새 id 생성 →
    //   SwiftUI 가 시트를 끝없이 dismiss/재표시(깜빡임·동작불가). key 기반 안정 id 로 고정.
    var id: String { key }
    let key: String; let descKey: String; let icon: String
}

struct GlossaryDetailSheet: View {
    let key: String; let descKey: String; let icon: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(AppColors.rule).frame(width: 36, height: 4).padding(.top, 10)
            ConceptGlyph(systemName: icon, size: 44, color: AppColors.accentDark)
            Text(String(localized: String.LocalizationValue(key)))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: String.LocalizationValue(descKey)))
                .font(.system(size: 15))
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .background(AppColors.paper0.ignoresSafeArea())
    }
}
