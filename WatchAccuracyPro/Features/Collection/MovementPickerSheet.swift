import SwiftUI

/// AddWatchView 의 무브먼트 picker — 200+ 캘리버 ForEach Picker 가 sheet open 시 jank 일으키던 문제 해소.
/// brand 우선 prefilter + .searchable 로 inflate 비용을 viewport 만큼만 부담.
/// 선택값 모델: nil = unknown, Watch.manualCaliberTag sentinel = manual entry, 그 외 = caliber id.
struct MovementPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCaliber: String?
    let manualEntryTag: String
    /// brand 텍스트 — 일치하는 brandFamilies 가진 무브먼트만 상단에 표시.
    let brandHint: String

    @State private var query: String = ""

    private var allMovements: [Movement] {
        MovementDatabase.shared.movements
    }

    /// brand prefilter — `Movement.brandFamilies` 가 brandHint 의 소문자 매칭 포함하면 우선 표시.
    private var brandRecommended: [Movement] {
        guard !brandHint.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let lower = brandHint.lowercased()
        return allMovements.filter { m in
            m.brandFamilies.contains { $0.lowercased().contains(lower) || lower.contains($0.lowercased()) }
        }
    }

    private var filtered: [Movement] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allMovements }
        return allMovements.filter { m in
            m.id.lowercased().contains(q)
                || m.brandFamilies.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Top option — unknown / manual
                Section {
                    Button {
                        selectedCaliber = nil
                        dismiss()
                    } label: {
                        row(title: String(localized: "addwatch.movement.unknown"), subtitle: nil, selected: selectedCaliber == nil)
                    }
                    Button {
                        selectedCaliber = manualEntryTag
                        dismiss()
                    } label: {
                        row(title: String(localized: "addwatch.movement.manual_entry"), subtitle: nil, selected: selectedCaliber == manualEntryTag)
                    }
                }
                // brand 매칭 추천 — query 비어 있을 때만 별 섹션으로.
                if query.isEmpty, !brandRecommended.isEmpty {
                    Section(String(localized: "addwatch.movement.section.recommended")) {
                        ForEach(brandRecommended, id: \.id) { m in
                            Button {
                                selectedCaliber = m.id
                                dismiss()
                            } label: {
                                row(title: m.id, subtitle: "\(m.bph) BPH", selected: selectedCaliber == m.id)
                            }
                        }
                    }
                }
                Section(query.isEmpty
                        ? String(localized: "addwatch.movement.section.all")
                        : String(localized: "addwatch.movement.section.results")) {
                    ForEach(filtered, id: \.id) { m in
                        Button {
                            selectedCaliber = m.id
                            dismiss()
                        } label: {
                            row(title: m.id, subtitle: "\(m.bph) BPH", selected: selectedCaliber == m.id)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: String(localized: "addwatch.movement.search.prompt"))
            .navigationTitle(String(localized: "addwatch.movement.picker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
        }
    }

    private func row(title: String, subtitle: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.ink0)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .contentShape(Rectangle())
    }
}
