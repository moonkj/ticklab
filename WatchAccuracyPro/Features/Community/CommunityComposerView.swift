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
    @State private var pendingPost: PendingPost?   // 크롭·검열 통과 → 캡션 입력(리뷰) 단계
    @State private var showTextReview = false      // Round 171: 글-전용 게시(사진 없음)
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
                    // Round 171: 사진 없이 글만 게시.
                    Button { showTextReview = true } label: {
                        sourceLabel(icon: "text.alignleft", key: "community.compose.text_only")
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
                guard let item else { return }
                Task {
                    let raw = try? await item.loadTransferable(type: Data.self)
                    await MainActor.run {
                        // 같은 사진을 다시 골라도 onChange가 재발화되도록 선택값 초기화.
                        photoItem = nil
                        if let raw, let ui = UIImage(data: raw) {
                            cropPayload = CropImagePayload(image: ui)
                        }
                    }
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
            .fullScreenCover(item: $pendingPost) { pending in
                CommunityReviewView(
                    imageData: pending.data,
                    onPost: { caption in pendingPost = nil; performUpload(data: pending.data, caption: caption) },
                    onCancel: { pendingPost = nil }
                )
            }
            .fullScreenCover(isPresented: $showTextReview) {
                // Round 171 글-전용 — 이미지 없이 캡션만 입력해 게시.
                CommunityReviewView(
                    imageData: nil,
                    onPost: { caption in showTextReview = false; performUpload(data: nil, caption: caption) },
                    onCancel: { showTextReview = false }
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

    /// 크롭 완료 → 이미지 검열 + EXIF strip → 캡션 입력(리뷰) 단계로.
    private func handleCropped(_ data: Data) {
        Task {
            // 온디바이스 사전 검열 (민감 콘텐츠 차단).
            if let ui = UIImage(data: data) {
                let result = await CommunityModerationService.screen(ui)
                if result == .blocked { moderationBlocked = true; return }
            }
            // EXIF strip 강제 (Hard Rule #8 개정 조건: 위치/메타 제거).
            let clean = EXIFStripper.strippedJPEG(from: data) ?? data
            await MainActor.run { pendingPost = PendingPost(data: clean) }
        }
    }

    /// 리뷰에서 "게시" → 캡션과 함께 업로드. 캡션 텍스트 검열은 리뷰 화면에서 이미 통과.
    /// data nil 이면 글-전용 게시(Round 171).
    private func performUpload(data: Data?, caption: String) {
        Task {
            isUploading = true
            do {
                try await service.uploadPost(imageData: data, brand: nil, caption: caption)
                isUploading = false
                dismiss()
            } catch CommunityService.UploadError.dailyLimit {
                isUploading = false
                uploadError = String(localized: "community.daily_limit.body")
            } catch {
                isUploading = false
                // 서버가 준 구체적 사유(insert 400/RLS/스토리지 status 등)를 그대로 노출 → 진단.
                uploadError = service.lastError ?? error.localizedDescription
            }
        }
    }
}

/// 크롭·이미지검열·EXIF strip 통과한 JPEG — 캡션 입력 단계로 전달.
struct PendingPost: Identifiable {
    let id = UUID()
    let data: Data
}

/// 게시 직전 리뷰 — 정사각 미리보기 + 짧은 캡션(선택) 입력 + 온디바이스 텍스트 검열.
/// 사진 작성기와 "공유카드 → 커뮤니티" 양쪽에서 재사용.
struct CommunityReviewView: View {
    /// nil 이면 글-전용 게시(사진 없음) — 이미지 미리보기 생략, 캡션 필수. Round 171.
    let imageData: Data?
    let onPost: (String) -> Void
    let onCancel: () -> Void

    @State private var caption = ""
    @State private var textBlocked = false
    @State private var blockMessage = ""
    @FocusState private var captionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let imageData, let ui = UIImage(data: imageData) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    captionField
                    Text(String(localized: "community.compose.anonymous_note"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.ink3)
                    communityGuidelineNote
                }
                .padding(20)
            }
            .background(AppColors.paper0)
            .navigationTitle(String(localized: "community.review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "community.review.post")) { submit() }
                        .fontWeight(.semibold)
                }
            }
            .alert(String(localized: "community.moderation.text.blocked.title"), isPresented: $textBlocked) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(blockMessage.isEmpty ? String(localized: "community.moderation.text.blocked.body") : blockMessage) }
        }
    }

    private var captionField: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField(String(localized: "community.caption.placeholder"),
                      text: $caption, axis: .vertical)
                .lineLimit(1...3)
                .focused($captionFocused)
                .font(AppTypography.body)
                .padding(12)
                .background(AppColors.paper1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                .onChange(of: caption) { _, new in
                    if new.count > CommunityTextModerator.maxLength {
                        caption = String(new.prefix(CommunityTextModerator.maxLength))
                    }
                }
            Text("\(caption.count)/\(CommunityTextModerator.maxLength)")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.ink3)
        }
    }

    private func submit() {
        // Round 171 글-전용: 사진이 없으면 내용이 비어 있으면 안 됨.
        if imageData == nil, caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blockMessage = String(localized: "community.compose.text_only.empty")
            textBlocked = true
            return
        }
        switch CommunityTextModerator.screen(caption) {
        case .allowed:
            onPost(caption)
        case .tradeBan:
            blockMessage = "거래·판매·연락처 유도는 허용되지 않습니다. TickLab은 감상·기록 커뮤니티예요."
            textBlocked = true
        case .profane, .tooLong:
            blockMessage = String(localized: "community.moderation.text.blocked.body")
            textBlocked = true
        }
    }

    /// 콘텐츠 정책 고지 — 거래 금지 등(가이드라인 요약).
    private var communityGuidelineNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("커뮤니티 가이드라인", systemImage: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.ink2)
            Text("거래·판매·가격 흥정·연락처 유도 금지 · 욕설/차별 금지 · 타인 사진 금지. 위반 시 삭제·제재될 수 있어요.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
