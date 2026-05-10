import SwiftUI
import SwiftData
import PhotosUI

struct AddWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var caliber: String? = nil
    @State private var purchaseDate: Date? = nil
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var suggestion: MovementMatcher.Suggestion?

    private let matcher = MovementMatcher()
    private let popularBrands = [
        "Rolex", "Omega", "Seiko", "Grand Seiko", "Tudor", "Hamilton", "Tissot",
        "Breitling", "IWC", "TAG Heuer", "Cartier", "Citizen", "Oris"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "addwatch.section.photo")) {
                    photoPicker
                }
                Section(String(localized: "addwatch.section.basic")) {
                    Picker(String(localized: "addwatch.brand"), selection: $brand) {
                        Text(String(localized: "common.unspecified")).tag("")
                        ForEach(popularBrands, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: brand) { _, _ in updateSuggestion() }

                    TextField(String(localized: "addwatch.model"), text: $model)
                        .onChange(of: model) { _, _ in updateSuggestion() }

                    DatePicker(
                        String(localized: "addwatch.purchase_date"),
                        selection: Binding(
                            get: { purchaseDate ?? Date() },
                            set: { purchaseDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }

                if let suggestion {
                    Section(String(localized: "addwatch.section.movement")) {
                        suggestionCard(suggestion)
                    }
                }
            }
            .navigationTitle(String(localized: "addwatch.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var photoPicker: some View {
        HStack(spacing: 12) {
            ZStack {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .frame(width: 72, height: 72)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            PhotosPicker(
                selection: $photoItem,
                matching: .images
            ) {
                Text(String(localized: "addwatch.choose_photo"))
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
        }
    }

    private func suggestionCard(_ suggestion: MovementMatcher.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "addwatch.suggested"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
            Text(suggestion.movement.id)
                .font(AppTypography.headline)
            Text(suggestion.movement.brandFamilies.joined(separator: " · "))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            HStack(spacing: 16) {
                Text("\(suggestion.movement.bph) BPH")
                Text("\(Int(suggestion.movement.liftAngleDegrees))° lift")
                if suggestion.movement.escapement != .swissLever {
                    Text(suggestion.movement.escapement.rawValue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.warning.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: 8) {
                Button(String(localized: "addwatch.accept_suggestion")) {
                    caliber = suggestion.movement.id
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(String(localized: "addwatch.skip_suggestion")) {
                    self.suggestion = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var canSave: Bool {
        !brand.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func updateSuggestion() {
        suggestion = matcher.suggest(brand: brand, model: model)
    }

    private func save() {
        let watch = Watch(
            brand: brand,
            model: model,
            caliber: caliber,
            purchaseDate: purchaseDate,
            photoData: photoData
        )
        modelContext.insert(watch)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    AddWatchView()
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
