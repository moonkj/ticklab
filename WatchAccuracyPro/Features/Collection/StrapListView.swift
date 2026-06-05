import SwiftData
import SwiftUI

/// Sprint 5 (P3-1): 시계별 스트랩/브레이슬릿 관리.
/// WatchDetailView serviceTab 또는 overview 탭에서 진입.
struct StrapListView: View {
    let watch: Watch
    @Environment(\.modelContext) private var context
    @State private var showingAdd = false
    @State private var editingStrap: Strap?

    private var straps: [Strap] {
        let id = watch.id
        let desc = FetchDescriptor<Strap>(
            predicate: #Predicate { $0.watch?.id == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    var body: some View {
        List {
            ForEach(straps) { strap in
                strapRow(strap)
                    .listRowBackground(Color.clear)
                    .onTapGesture { editingStrap = strap }
            }
            .onDelete { offsets in
                offsets.forEach { i in context.delete(straps[i]) }
                try? context.save()
            }
        }
        .listStyle(.plain)
        .navigationTitle(String(localized: "strap.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            StrapComposerView(watch: watch)
        }
        .sheet(item: $editingStrap) { strap in
            StrapComposerView(watch: watch, existing: strap)
        }
        .overlay {
            if straps.isEmpty {
                EmptyState(
                    icon: "watch.analog",
                    title: String(localized: "strap.empty.title"),
                    message: String(localized: "strap.empty.body")
                )
            }
        }
    }

    private func strapRow(_ strap: Strap) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(AppColors.paper2).frame(width: 56, height: 56)
                if let data = strap.photoData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ConceptGlyph(systemName: "watch.analog", size: 22, color: AppColors.ink3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(strap.name.isEmpty ? StrapMaterialHelper.displayName(for: strap.material) : strap.name)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.ink0)
                    if strap.isNearReplacement {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(AppColors.warning)
                    }
                }
                Text(StrapMaterialHelper.displayName(for: strap.material) + (strap.colorName.isEmpty ? "" : " · \(strap.colorName)"))
                    .font(.system(size: 12)).foregroundStyle(AppColors.ink2)
                HStack(spacing: 12) {
                    if let threshold = strap.replaceThreshold {
                        Text(String(format: NSLocalizedString("strap.threshold", comment: ""), threshold))
                            .font(.system(size: 11)).foregroundStyle(AppColors.ink3)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(AppColors.ink3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - StrapMaterialHelper

/// SwiftData 에 저장된 원문(한국어) 소재 키 → 현재 로케일 표시명 변환.
/// rawValue 변경 불가(스키마 보존) — 표시 시에만 이 헬퍼를 통한다.
enum StrapMaterialHelper {
    private static let map: [String: String] = [
        "가죽":   "strap.material.leather",
        "러버":   "strap.material.rubber",
        "나토":   "strap.material.nato",
        "메탈":   "strap.material.metal",
        "패브릭": "strap.material.fabric",
        "세라믹": "strap.material.ceramic",
        "기타":   "strap.material.other",
    ]

    /// 알려진 소재는 현지화된 이름으로, 커스텀 자유입력은 그대로 반환.
    static func displayName(for raw: String) -> String {
        guard let key = map[raw] else { return raw }
        return String(localized: String.LocalizationValue(key))
    }
}

struct StrapComposerView: View {
    let watch: Watch
    var existing: Strap?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var material = ""
    @State private var colorName = ""
    @State private var source = ""
    @State private var note = ""
    @State private var replaceThresholdText = ""
    @State private var showTextFilterAlert = false

    // rawValue 는 SwiftData 에 저장되는 키 — 변경 금지.
    // 화면 표시는 StrapMaterialHelper.displayName(for:) 사용.
    private static let materials = ["가죽", "러버", "나토", "메탈", "패브릭", "세라믹", "기타"]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "strap.section.basic")) {
                    TextField(String(localized: "strap.name"), text: $name)
                    Picker(String(localized: "strap.material"), selection: $material) {
                        ForEach(Self.materials, id: \.self) {
                            Text(StrapMaterialHelper.displayName(for: $0)).tag($0)
                        }
                    }
                    TextField(String(localized: "strap.color"), text: $colorName)
                    TextField(String(localized: "strap.source"), text: $source)
                }
                Section(String(localized: "strap.section.usage")) {
                    HStack {
                        Text(String(localized: "strap.replace_threshold"))
                        Spacer()
                        TextField(String(localized: "strap.threshold_placeholder"),
                                  text: $replaceThresholdText).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                    }
                }
                Section(String(localized: "service.section.note")) {
                    TextField(String(localized: "strap.note"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existing == nil ? String(localized: "strap.add.title") : String(localized: "strap.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) { save() }.fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
            .alert(String(localized: "text.filter.blocked.title"), isPresented: $showTextFilterAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(String(localized: "text.filter.blocked.body")) }
        }
    }

    private func loadExisting() {
        guard let s = existing else { return }
        name = s.name; material = s.material; colorName = s.colorName
        source = s.source ?? ""; note = s.note
        replaceThresholdText = s.replaceThreshold.map { "\($0)" } ?? ""
    }

    private func save() {
        // 욕설 등 부적절 텍스트 사전 필터(자유 입력 필드만 — 소재 picker/숫자 제외).
        let userTexts = [name, colorName, source, note]
        if userTexts.contains(where: { CommunityTextModerator.containsProfanity($0) }) {
            showTextFilterAlert = true
            return
        }
        let strap = existing ?? Strap(watch: watch)
        strap.name = name; strap.material = material; strap.colorName = colorName
        strap.source = source.isEmpty ? nil : source; strap.note = note
        strap.replaceThreshold = replaceThresholdText.isEmpty ? nil : Int(replaceThresholdText)
        if existing == nil { context.insert(strap) }
        try? context.save()
        dismiss()
    }
}
