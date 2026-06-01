import SwiftUI
import PhotosUI

/// 커뮤니티 사진 작성기 — 라이브러리/카메라 → 4:3 크롭 → 온디바이스 검열 → 업로드.
/// 하루 1장(서버 강제 + 클라 가드). 익명 게시.
struct CommunityComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CommunityService.shared

    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var cropPayload: CropImagePayload?
    @State private var isUploading = false
    @State private var moderationBlocked = false
    @State private var uploadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "camera.aperture")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.ink3)
                Text(String(localized: "community.compose.hint"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                VStack(spacing: 12) {
                    Button { showingLibrary = true } label: {
                        sourceLabel(icon: "photo.on.rectangle", key: "photo.source.library")
                    }
                    Button { showingCamera = true } label: {
                        sourceLabel(icon: "camera", key: "photo.source.camera")
                    }
                }
                .padding(.horizontal, 32)
                Spacer()
                Text(String(localized: "community.compose.anonymous_note"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.ink3)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.paper0)
            .navigationTitle(String(localized: "community.compose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .photosPicker(isPresented: $showingLibrary, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let raw = try? await item?.loadTransferable(type: Data.self),
                          let ui = UIImage(data: raw) else { return }
                    await MainActor.run { cropPayload = CropImagePayload(image: ui) }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraImagePicker(imageData: Binding(
                    get: { nil },
                    set: { newData in
                        if let raw = newData, let ui = UIImage(data: raw) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                cropPayload = CropImagePayload(image: ui)
                            }
                        }
                    }
                ))
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $cropPayload) { payload in
                PhotoCropView(
                    image: payload.image,
                    aspect: 1.0,   // 인스타 스타일 정사각(1:1) — 커뮤니티 피드.
                    onComplete: { data in cropPayload = nil; handleCropped(data) },
                    onCancel: { cropPayload = nil }
                )
            }
            .overlay { if isUploading { uploadingOverlay } }
            .alert(String(localized: "community.moderation.blocked.title"), isPresented: $moderationBlocked) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(String(localized: "community.moderation.blocked.body")) }
            .alert(String(localized: "community.upload.error"), isPresented: Binding(
                get: { uploadError != nil }, set: { if !$0 { uploadError = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { uploadError = nil }
            } message: { Text(uploadError ?? "") }
        }
    }

    private func sourceLabel(icon: String, key: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(String(localized: String.LocalizationValue(key)))
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(AppColors.ink0)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColors.paper1)
        .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
        .clipShape(Capsule())
    }

    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView().tint(.white).scaleEffect(1.4)
        }
    }

    private func handleCropped(_ data: Data) {
        Task {
            // 온디바이스 사전 검열 (민감 콘텐츠 차단).
            if let ui = UIImage(data: data) {
                let result = await CommunityModerationService.screen(ui)
                if result == .blocked { moderationBlocked = true; return }
            }
            // EXIF strip 강제 (Hard Rule #8 개정 조건: 위치/메타 제거).
            let clean = EXIFStripper.strippedJPEG(from: data) ?? data
            isUploading = true
            do {
                try await service.uploadPost(imageData: clean, brand: nil)
                isUploading = false
                dismiss()
            } catch CommunityService.UploadError.dailyLimit {
                isUploading = false
                uploadError = String(localized: "community.daily_limit.body")
            } catch {
                isUploading = false
                uploadError = error.localizedDescription
            }
        }
    }
}
