import SwiftUI
import PhotosUI
import SwiftData

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
    /// 진행 중 위클리 테마 — 리뷰 화면 "이번 주 테마로 게시" 토글용. nil = 테마 없음.
    @State private var activeTheme: Community.Theme?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                ConceptGlyph(systemName: "camera.aperture", size: 44)
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
            .task { activeTheme = await service.fetchActiveTheme() }
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
                    theme: activeTheme,
                    onPost: { _ in },   // 미사용(상세 콜백 사용) — 호환 시그니처.
                    onPostDetailed: { caption, brand, themeID in
                        pendingPost = nil
                        performUpload(data: pending.data, caption: caption, brand: brand, themeID: themeID)
                    },
                    onCancel: { pendingPost = nil }
                )
            }
            .fullScreenCover(isPresented: $showTextReview) {
                // Round 171 글-전용 — 이미지 없이 캡션만 입력해 게시.
                CommunityReviewView(
                    imageData: nil,
                    theme: activeTheme,
                    onPost: { _ in },
                    onPostDetailed: { caption, brand, themeID in
                        showTextReview = false
                        performUpload(data: nil, caption: caption, brand: brand, themeID: themeID)
                    },
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
            ConceptGlyph(systemName: icon, size: 17)
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
            AnimatedEmptyIcon(icon: "paperplane.fill")   // 가운데 아이콘 + 회전 링(앱 공통 로딩).
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

    /// 리뷰에서 "게시" → 캡션·브랜드·테마와 함께 업로드. 캡션 텍스트 검열은 리뷰 화면에서 이미 통과.
    /// data nil 이면 글-전용 게시(Round 171). brand = 내 컬렉션 화이트리스트 선택값(nil 가능).
    private func performUpload(data: Data?, caption: String, brand: String?, themeID: String?) {
        Task {
            isUploading = true
            do {
                try await service.uploadPost(imageData: data, brand: brand, caption: caption, themeID: themeID)
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
    /// 진행 중 위클리 테마 — 있으면 "이번 주 테마로 게시" 토글 노출. nil = 토글 없음.
    var theme: Community.Theme? = nil
    /// 기존 호출부 호환(공유카드·설정) — 캡션만 전달.
    let onPost: (String) -> Void
    /// 스트림C(커뮤니티 작성기 전용) — 캡션 + 브랜드 + 테마ID 전달. 설정 시 brand/theme UI 노출.
    var onPostDetailed: ((String, String?, String?) -> Void)? = nil
    let onCancel: () -> Void

    /// 브랜드 칩 화이트리스트 — 내 컬렉션 브랜드(distinct). 시세·모델명 입력 금지(거래유도 방지).
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]

    @State private var caption = ""
    @State private var selectedBrand: String?           // 선택된 브랜드 칩(nil = 미선택)
    @State private var participateTheme = true           // 테마 있으면 기본 참여 ON
    @State private var textBlocked = false
    @State private var blockMessage = ""
    @State private var submitted = false   // 중복 게시 방지 — 1회 제출 후 잠금.
    @FocusState private var captionFocused: Bool

    /// 내 컬렉션 브랜드(distinct, 정렬). 브랜드 칩 선택지.
    private var myBrands: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for w in watches {
            let b = w.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !b.isEmpty, !seen.contains(b.lowercased()) else { continue }
            seen.insert(b.lowercased())
            out.append(b)
        }
        return out.sorted()
    }

    /// brand/theme 입력 UI 노출 여부 — 커뮤니티 작성기(상세 콜백) 경로에서만.
    private var showsTagging: Bool { onPostDetailed != nil }

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
                    if showsTagging {
                        if !myBrands.isEmpty { brandPicker }
                        if let theme { themeToggle(theme) }
                    }
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
                    if submitted {
                        LoadingRing(size: 20)   // 누르면 즉시 로딩 링 — "멈춘 줄 알고 재탭" 방지.
                    } else {
                        Button(String(localized: "community.review.post")) { submit() }
                            .fontWeight(.semibold)
                    }
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

    /// 브랜드 칩 — 내 컬렉션 브랜드 화이트리스트에서 1개 선택(토글). 시세·모델명 입력 없음.
    private var brandPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "community.brand.picker.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(myBrands, id: \.self) { brand in
                        let on = (selectedBrand == brand)
                        Button {
                            selectedBrand = on ? nil : brand   // 다시 탭하면 해제.
                        } label: {
                            Text(brand)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(on ? AppColors.paper0 : AppColors.ink1)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? AppColors.ink0 : AppColors.paper1)
                                .overlay(Capsule().stroke(AppColors.rule, lineWidth: on ? 0 : 1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            Text(String(localized: "community.brand.picker.note"))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "이번 주 테마로 게시" 토글 — 진행 중 위클리 테마가 있을 때만.
    private func themeToggle(_ theme: Community.Theme) -> some View {
        Toggle(isOn: $participateTheme) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "community.theme.post_toggle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Text(theme.title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.accentDark)
                    .lineLimit(1)
            }
        }
        .tint(AppColors.accentDark)
        .padding(12)
        .background(AppColors.accent50.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func submit() {
        guard !submitted else { return }   // 중복 게시 방지 — 멈춘 줄 알고 재탭해도 1회만.
        // Round 171 글-전용: 사진이 없으면 내용이 비어 있으면 안 됨.
        if imageData == nil, caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blockMessage = String(localized: "community.compose.text_only.empty")
            textBlocked = true
            return
        }
        switch CommunityTextModerator.screen(caption) {
        case .allowed:
            submitted = true
            if let onPostDetailed {
                // 테마 참여 토글이 켜져 있을 때만 theme id 귀속.
                let themeID = (theme != nil && participateTheme) ? theme?.id : nil
                onPostDetailed(caption, selectedBrand, themeID)
            } else {
                onPost(caption)
            }
        case .tradeBan:
            blockMessage = String(localized: "community.moderation.trade.blocked.body")
            textBlocked = true
        case .profane, .tooLong:
            blockMessage = String(localized: "community.moderation.text.blocked.body")
            textBlocked = true
        }
    }

    /// 콘텐츠 정책 고지 — 거래 금지 등(가이드라인 요약).
    private var communityGuidelineNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "community.guideline.title"), systemImage: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.ink2)
            Text(String(localized: "community.guideline.body"))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
