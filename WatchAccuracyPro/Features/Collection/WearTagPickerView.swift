import SwiftData
import SwiftUI

/// Sprint 4 (P2-18): 착용 기록 이벤트 태그 picker — 바텀 시트.
/// 착용 토글 후 바로 표시. 스킵 가능.
struct WearTagPickerView: View {
    let wearLog: WearLog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selected: Set<String> = []
    @State private var customTag: String = ""
    @State private var isHighlight: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "weartag.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.ink2)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                // 프리셋 태그 그리드
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 10) {
                    ForEach(WearTag.allCases) { tag in
                        tagChip(tag.rawValue, icon: tag.icon,
                                isSelected: selected.contains(tag.rawValue)) {
                            toggle(tag.rawValue)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // 커스텀 태그
                HStack(spacing: 8) {
                    TextField(String(localized: "weartag.custom.placeholder"), text: $customTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addCustomTag() }
                    Button(String(localized: "common.add")) { addCustomTag() }
                        .disabled(customTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accentDark)
                }
                .padding(.horizontal, 20)

                // 선택된 커스텀 태그
                let customTags = selected.filter { tag in !WearTag.allCases.map(\.rawValue).contains(tag) }
                if !customTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(customTags), id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag).font(.system(size: 12))
                                    Button { selected.remove(tag) } label: {
                                        Image(systemName: "xmark").font(.system(size: 9))
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(AppColors.accent50)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()

                PrimaryButton(String(localized: "weartag.save"), style: .accent, isEnabled: true) {
                    save()
                }
                .padding(.horizontal, 20)

                // 하이라이트 토글
        Toggle(isOn: $isHighlight) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill").foregroundStyle(AppColors.accent)
                Text(String(localized: "weartag.highlight"))
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(.horizontal, 20)
        .tint(AppColors.accent)

                PrimaryButton(String(localized: "weartag.save"), style: .accent, isEnabled: true) {
                    save()
                }
                .padding(.horizontal, 20)

                Button(String(localized: "weartag.skip")) { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
            .navigationTitle(String(localized: "weartag.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
        }
        .onAppear {
            selected = Set(wearLog.tags)
            isHighlight = wearLog.isHighlight
        }
        .presentationDetents([.medium])
    }

    private func tagChip(_ label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? AppColors.primaryDeep : AppColors.ink0)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(isSelected
                ? LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [AppColors.paper2, AppColors.paper2],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ tag: String) {
        if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
    }

    private func addCustomTag() {
        let trimmed = customTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selected.insert(trimmed)
        customTag = ""
    }

    private func save() {
        wearLog.tags = Array(selected).sorted()
        wearLog.isHighlight = isHighlight
        try? context.save()
        dismiss()
    }
}
