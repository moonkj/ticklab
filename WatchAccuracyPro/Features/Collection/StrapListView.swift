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
                    Image(systemName: "watch.analog")
                        .font(.system(size: 22)).foregroundStyle(AppColors.ink3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(strap.name.isEmpty ? strap.material : strap.name)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.ink0)
                    if strap.isNearReplacement {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(AppColors.warning)
                    }
                }
                Text(strap.material + (strap.colorName.isEmpty ? "" : " · \(strap.colorName)"))
                    .font(.system(size: 12)).foregroundStyle(AppColors.ink2)
                HStack(spacing: 12) {
                    Label("\(strap.wearCount)\(String(localized: "strap.wears"))",
                          systemImage: "repeat").font(.system(size: 11)).foregroundStyle(AppColors.ink3)
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
    @State private var wearCountText = "0"
    @State private var replaceThresholdText = ""

    private static let materials = ["가죽", "러버", "나토", "메탈", "패브릭", "세라믹", "기타"]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "strap.section.basic")) {
                    TextField(String(localized: "strap.name"), text: $name)
                    Picker(String(localized: "strap.material"), selection: $material) {
                        ForEach(Self.materials, id: \.self) { Text($0).tag($0) }
                    }
                    TextField(String(localized: "strap.color"), text: $colorName)
                    TextField(String(localized: "strap.source"), text: $source)
                }
                Section(String(localized: "strap.section.usage")) {
                    HStack {
                        Text(String(localized: "strap.wears"))
                        Spacer()
                        TextField("0", text: $wearCountText).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).frame(width: 60)
                    }
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
        }
    }

    private func loadExisting() {
        guard let s = existing else { return }
        name = s.name; material = s.material; colorName = s.colorName
        source = s.source ?? ""; note = s.note
        wearCountText = "\(s.wearCount)"
        replaceThresholdText = s.replaceThreshold.map { "\($0)" } ?? ""
    }

    private func save() {
        let strap = existing ?? Strap(watch: watch)
        strap.name = name; strap.material = material; strap.colorName = colorName
        strap.source = source.isEmpty ? nil : source; strap.note = note
        strap.wearCount = Int(wearCountText) ?? 0
        strap.replaceThreshold = replaceThresholdText.isEmpty ? nil : Int(replaceThresholdText)
        if existing == nil { context.insert(strap) }
        try? context.save()
        dismiss()
    }
}
