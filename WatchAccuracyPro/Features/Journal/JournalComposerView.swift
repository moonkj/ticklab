import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Journal entry 작성 sheet. 시계 선택 + 코멘트 + mood + 사진 (Phase 1: placeholder).
struct JournalComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]

    /// Round 118 (검토B High): WatchDetail 일기 탭에서 직접 진입 시 미리 선택된 시계.
    var defaultWatch: Watch? = nil

    @State private var selectedWatch: Watch?
    @State private var entryText: String = ""
    @State private var mood: Mood = .neutral
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var pickedPhotoCount: Int = 0
    @State private var isProcessingPhotos: Bool = false
    @FocusState private var bodyFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    watchPicker
                    moodPicker
                    bodyEditor
                    photoSection
                }
                .padding(20)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "journal.compose.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) { save() }
                        .fontWeight(.medium)
                        .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && pickedPhotoCount == 0)
                }
            }
            .onAppear {
                // Round 118: defaultWatch 가 있으면 미리 선택.
                if selectedWatch == nil {
                    selectedWatch = defaultWatch ?? watches.first
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { bodyFocused = true }
            }
        }
    }

    private var watchPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: String(localized: "journal.compose.watch"))
            Menu {
                Button(String(localized: "journal.compose.no_watch")) { selectedWatch = nil }
                ForEach(watches) { watch in
                    Button {
                        selectedWatch = watch
                    } label: {
                        Text("\(watch.brand) \(watch.model)")
                    }
                }
            } label: {
                HStack {
                    Text(selectedWatch.map { "\($0.brand) \($0.model)" } ?? String(localized: "journal.compose.no_watch"))
                        .foregroundStyle(AppColors.ink0)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(AppColors.ink2)
                }
                .padding(12)
                .background(AppColors.paper1)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.md).stroke(AppColors.rule, lineWidth: 1))
            }
        }
    }

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: String(localized: "journal.compose.mood"))
            HStack(spacing: 8) {
                ForEach(Mood.allCases, id: \.self) { m in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.12)) { mood = m }
                    } label: {
                        VStack(spacing: 2) {
                            Text(m.emoji).font(.system(size: 22))
                            Text(m.localizedName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(mood == m ? AppColors.accentDark : AppColors.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        // Round 66: accent50 너무 옅음 → accent100 강화.
                        .background(mood == m ? AppColors.accent100 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .stroke(mood == m ? AppColors.accent : AppColors.rule, lineWidth: mood == m ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: String(localized: "journal.compose.body"))
            ZStack(alignment: .topLeading) {
                if entryText.isEmpty {
                    Text(String(localized: "journal.compose.placeholder"))
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.ink3)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
                TextEditor(text: $entryText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .focused($bodyFocused)
            }
            .frame(minHeight: 150)
            .background(AppColors.paper1)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.md).stroke(AppColors.rule, lineWidth: 1))
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: String(localized: "journal.compose.photos"))
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 4,
                matching: .images
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                    Text(String(format: NSLocalizedString("journal.compose.photo_count", comment: ""), pickedPhotoCount))
                        .font(.system(size: 13))
                    if isProcessingPhotos {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .foregroundStyle(AppColors.accent)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.accent50)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
            // Round 170: PhotosPickerItem → Data 변환 + EXIF strip 후 메모리에 보관.
            // save() 호출 시 disk 로 영구 저장 (orphan 방지).
            .onChange(of: photoItems) { _, newItems in
                Task {
                    isProcessingPhotos = true
                    var datas: [Data] = []
                    for item in newItems {
                        if let raw = try? await item.loadTransferable(type: Data.self),
                           let stripped = EXIFStripper.strippedJPEG(from: raw) {
                            datas.append(stripped)
                        }
                    }
                    photoDatas = datas
                    pickedPhotoCount = datas.count
                    isProcessingPhotos = false
                }
            }
            // Selected photo thumbnails preview.
            if !photoDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                            if let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
    }

    private func save() {
        // Round 170: 사진을 영구 저장하고 path 를 entry 에 보관.
        let paths = photoDatas.compactMap { EXIFStripper.savePhoto($0) }
        let entry = JournalEntry(
            watch: selectedWatch,
            timestamp: .init(),
            body: entryText.trimmingCharacters(in: .whitespacesAndNewlines),
            photoPaths: paths,
            mood: mood
        )
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}
