import PhotosUI
import SwiftData
import SwiftUI

/// Sprint 7 (P2-4): 역할별 사진 갤러리.
/// WatchDetail → "추억" 탭 또는 상단 카메라 메뉴에서 진입.
struct PhotoGalleryView: View {
    let watch: Watch
    @Environment(\.modelContext) private var context
    @State private var selectedRole: PhotoRole = .hero
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPicker = false
    @State private var selectedPhoto: WatchPhoto?

    private var photos: [WatchPhoto] {
        let id = watch.id
        let desc = FetchDescriptor<WatchPhoto>(
            predicate: #Predicate { $0.watch?.id == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    private var photosByRole: [PhotoRole: [WatchPhoto]] {
        Dictionary(grouping: photos, by: \.role)
    }

    // 완성도 게이지
    private var completionRoles: Set<PhotoRole> {
        Set(photos.map(\.role))
    }
    private var completionFraction: Double {
        let total = PhotoRole.allCases.filter { $0 != .other }.count
        let done = completionRoles.filter { $0 != .other }.count
        return total > 0 ? Double(done) / Double(total) : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                completionCard
                rolePicker
                photoGrid
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "gallery.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: photoItem) { _, new in
            guard let new else { return }
            Task {
                guard let raw = try? await new.loadTransferable(type: Data.self),
                      let processed = EXIFStripper.strippedJPEG(from: raw, watchMode: true) else { return }
                await MainActor.run {
                    let photo = WatchPhoto(watch: watch, role: selectedRole, photoData: processed)
                    context.insert(photo)
                    try? context.save()
                    photoItem = nil
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
    }

    // MARK: - 완성도 카드

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "gallery.completion.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.accentDark)
                Spacer()
                Text(String(format: "%.0f%%", completionFraction * 100))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.accentDark)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.paper2).frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * completionFraction, height: 8)
                }
            }
            .frame(height: 8)
            HStack(spacing: 8) {
                ForEach(PhotoRole.allCases.filter { $0 != .other }) { role in
                    HStack(spacing: 3) {
                        Image(systemName: completionRoles.contains(role) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(completionRoles.contains(role) ? AppColors.success : AppColors.ink3)
                        Text(role.localizedName)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.ink2)
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [AppColors.accent50, AppColors.paper1],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 역할 탭

    private var rolePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotoRole.allCases) { role in
                    let count = photosByRole[role]?.count ?? 0
                    Button {
                        selectedRole = role
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: role.icon).font(.system(size: 11))
                            Text(role.localizedName).font(.system(size: 12, weight: .semibold))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(.white.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundStyle(selectedRole == role ? AppColors.primaryDeep : AppColors.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(selectedRole == role
                            ? LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                             startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [AppColors.paper2, AppColors.paper2],
                                             startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 사진 그리드

    private var photoGrid: some View {
        let filtered = photosByRole[selectedRole] ?? []
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                         spacing: 3) {
            ForEach(filtered) { photo in
                if let img = UIImage(data: photo.photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipped()
                        .onTapGesture { selectedPhoto = photo }
                }
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: WatchPhoto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let img = UIImage(data: photo.photoData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(String(localized: "common.close")) { dismiss() }
                                .tint(.white)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .destructive) {
                                context.delete(photo)
                                try? context.save()
                                dismiss()
                            } label: {
                                Image(systemName: "trash").tint(.red)
                            }
                        }
                    }
            }
        }
    }
}
