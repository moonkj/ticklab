import PhotosUI
import SwiftUI

/// Sprint 10 (P3-13): 사용자 프로필 — UserDefaults 기반 로컬 저장.
/// CloudKit Phase 3에서 서버 동기화 예정.
struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var collectionStartYear: String = ""
    @State private var favoriteBrands: String = ""
    /// Round 174: 커뮤니티 피드 아바타 하단에 노출할 대표 메이커(좋아하는 브랜드 중 1개).
    @State private var repBrand: String = ""
    @State private var isDealerBadge: Bool = false
    @State private var bio: String = ""
    @State private var profilePhotoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var referralCode: String = ReferralService.referralCode
    /// 욕설 필터 차단 alert (커뮤니티 캡션 필터와 동일 정책).
    @State private var showTextFilterAlert: Bool = false
    /// 닉네임 규칙 — 중복 선점/30일 변경 제한.
    @State private var originalName: String = ""
    @State private var showNameTakenAlert: Bool = false
    @State private var showCooldownAlert: Bool = false
    @State private var cooldownDaysRemaining: Int = 0
    @State private var isSaving: Bool = false

    private let nameKey = "ticklab.profile.name"
    private let nameChangedKey = "ticklab.profile.nameChangedAt"
    private let yearKey = "ticklab.profile.startYear"
    private let brandsKey = "ticklab.profile.brands"
    private let repBrandKey = "ticklab.profile.repBrand"
    private let dealerKey = "ticklab.profile.isDealer"
    private let bioKey = "ticklab.profile.bio"
    private let photoKey = "ticklab.profile.photoData"
    /// 닉네임 변경 제한 기간(30일).
    private let nameCooldown: TimeInterval = 30 * 24 * 3600

    var body: some View {
        NavigationStack {
            Form {
                // 프로필 사진 + 이름
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.paper2)
                                    .frame(width: 72, height: 72)
                                if let data = profilePhotoData, let img = UIImage(data: data) {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(AppColors.ink3)
                                }
                                Circle()
                                    .stroke(AppColors.rule, lineWidth: 1)
                                    .frame(width: 72, height: 72)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(AppColors.accentDark)
                                    .clipShape(Circle())
                                    .offset(x: 24, y: 24)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(String(localized: "profile.name"), text: $displayName)
                                .font(.system(size: 17, weight: .semibold))
                            Text(String(localized: "profile.name.hint"))
                                .font(.caption)
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text(String(localized: "profile.name.rules"))
                        .font(.caption2)
                        .foregroundStyle(AppColors.ink3)
                }

                Section(String(localized: "profile.section.collector")) {
                    // 시작 연도 — 선택형(Menu).
                    HStack {
                        Text(String(localized: "profile.start_year"))
                        Spacer()
                        Menu {
                            Button(String(localized: "common.unspecified")) { collectionStartYear = "" }
                            ForEach(yearOptions, id: \.self) { y in
                                Button(String(y)) { collectionStartYear = String(y) }
                            }
                        } label: {
                            Text(collectionStartYear.isEmpty ? String(localized: "common.unspecified") : collectionStartYear)
                                .foregroundStyle(collectionStartYear.isEmpty ? AppColors.ink3 : AppColors.ink0)
                        }
                    }
                    // 좋아하는 브랜드 — 선택형(추가 메뉴 + 칩 제거).
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "profile.fav_brands"))
                            Spacer()
                            Menu {
                                ForEach(WatchBrands.popular, id: \.self) { b in
                                    Button { addFavoriteBrand(b) } label: {
                                        if favoriteBrandList.contains(b) { Label(b, systemImage: "checkmark") } else { Text(b) }
                                    }
                                }
                            } label: {
                                Label(String(localized: "common.add"), systemImage: "plus.circle")
                            }
                        }
                        if !favoriteBrandList.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                                ForEach(favoriteBrandList, id: \.self) { b in
                                    Button { removeFavoriteBrand(b) } label: {
                                        HStack(spacing: 4) {
                                            Text(b).font(.system(size: 12)).lineLimit(1)
                                            Image(systemName: "xmark").font(.system(size: 9))
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(AppColors.paper2).clipShape(Capsule())
                                        .foregroundStyle(AppColors.ink1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    // Round 174: 대표 메이커 — 커뮤니티 피드 아바타 하단 칩으로 노출(좋아하는 브랜드 중 선택).
                    HStack {
                        Text(String(localized: "profile.rep_brand"))
                        Spacer()
                        Menu {
                            Button(String(localized: "common.unspecified")) { repBrand = "" }
                            ForEach(favoriteBrandList, id: \.self) { b in
                                Button(b) { repBrand = b }
                            }
                        } label: {
                            Text(repBrand.isEmpty ? String(localized: "common.unspecified") : repBrand)
                                .foregroundStyle(repBrand.isEmpty ? AppColors.ink3 : AppColors.ink0)
                        }
                        .disabled(favoriteBrandList.isEmpty)
                    }
                    TextField(String(localized: "profile.bio"), text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Toggle(isOn: $isDealerBadge) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "profile.dealer_badge"))
                                .font(.system(size: 15, weight: .semibold))
                            Text(String(localized: "profile.dealer_badge.hint"))
                                .font(.caption)
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                }

                Section(String(localized: "profile.section.invite")) {
                    HStack {
                        Text(String(localized: "referral.code.label"))
                        Spacer()
                        Text(referralCode)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.accentDark)
                    }
                    .onTapGesture {
                        UIPasteboard.general.string = referralCode
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
            .navigationTitle(String(localized: "profile.nav.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) {
                        // 욕설·중복·변경제한 통과 시에만 저장·dismiss. 차단되면 editor 유지.
                        Task { if await save() { dismiss() } }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .onAppear { load() }
            .alert(String(localized: "text.filter.blocked.title"), isPresented: $showTextFilterAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "text.filter.blocked.body"))
            }
            .alert(String(localized: "profile.name.taken.title"), isPresented: $showNameTakenAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "profile.name.taken.body"))
            }
            .alert(String(localized: "profile.name.cooldown.title"), isPresented: $showCooldownAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(format: String(localized: "profile.name.cooldown.body"), cooldownDaysRemaining))
            }
            .onChange(of: photoItem) { _, new in
                guard let new else { return }
                Task {
                    if let raw = try? await new.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            profilePhotoData = EXIFStripper.strippedJPEG(from: raw)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 선택형 헬퍼

    /// 시작 연도 옵션 — 1950 ~ 올해(내림차순).
    private var yearOptions: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((1950...current).reversed())
    }

    /// favoriteBrands(콤마 구분) → 배열.
    private var favoriteBrandList: [String] {
        favoriteBrands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func addFavoriteBrand(_ b: String) {
        var list = favoriteBrandList
        guard !list.contains(b) else { return }
        list.append(b)
        favoriteBrands = list.joined(separator: ", ")
    }
    private func removeFavoriteBrand(_ b: String) {
        favoriteBrands = favoriteBrandList.filter { $0 != b }.joined(separator: ", ")
        if repBrand == b { repBrand = "" }   // 대표 메이커로 지정돼 있었다면 해제.
    }

    private func load() {
        let d = UserDefaults.standard
        displayName = d.string(forKey: nameKey) ?? ""
        originalName = displayName
        collectionStartYear = d.string(forKey: yearKey) ?? ""
        favoriteBrands = d.string(forKey: brandsKey) ?? ""
        repBrand = d.string(forKey: repBrandKey) ?? ""
        isDealerBadge = d.bool(forKey: dealerKey)
        bio = d.string(forKey: bioKey) ?? ""
        profilePhotoData = d.data(forKey: photoKey)
    }

    /// 저장 성공 여부 반환. 차단 시 false (저장 안 함, alert 표시).
    /// 닉네임은 ⓐ욕설 ⓑ30일 변경제한 ⓒ타인 선점 중복을 통과해야 변경 가능.
    /// 자유 입력 텍스트(이름/좋아하는 브랜드/소개글)만 욕설 검사. 연도·딜러 토글·사진은 제외.
    private func save() async -> Bool {
        let userTexts = [displayName, favoriteBrands, bio]
        if userTexts.contains(where: { CommunityTextModerator.containsProfanity($0) }) {
            showTextFilterAlert = true
            return false
        }
        let d = UserDefaults.standard
        let newName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameChanged = newName != originalName.trimmingCharacters(in: .whitespacesAndNewlines)

        if nameChanged {
            // ⓑ 30일 변경 제한 — 마지막 변경 후 30일 경과해야 변경 가능.
            if let changedAt = d.object(forKey: nameChangedKey) as? Date {
                let elapsed = Date().timeIntervalSince(changedAt)
                if elapsed < nameCooldown {
                    cooldownDaysRemaining = max(1, Int(ceil((nameCooldown - elapsed) / 86_400)))
                    showCooldownAlert = true
                    return false
                }
            }
            // ⓒ 타인 선점 중복 — 비어있지 않을 때만(빈 닉네임은 로컬 컬렉터 폴백).
            if !newName.isEmpty {
                isSaving = true
                let taken = await CommunityService.shared.isNicknameTaken(newName)
                isSaving = false
                if taken {
                    showNameTakenAlert = true
                    return false
                }
            }
        }

        d.set(displayName, forKey: nameKey)
        d.set(collectionStartYear, forKey: yearKey)
        d.set(favoriteBrands, forKey: brandsKey)
        d.set(repBrand, forKey: repBrandKey)
        d.set(isDealerBadge, forKey: dealerKey)
        d.set(bio, forKey: bioKey)
        d.set(profilePhotoData, forKey: photoKey)

        if nameChanged {
            d.set(Date(), forKey: nameChangedKey)        // 변경 시각 갱신 → 다음 변경까지 30일
            originalName = newName
            if !newName.isEmpty { await CommunityService.shared.registerNickname(newName) }
        }
        return true
    }
}

/// 설정 화면 상단 hero card용 프로필 요약 accessor
struct UserProfile {
    static var displayName: String {
        UserDefaults.standard.string(forKey: "ticklab.profile.name") ?? ""
    }
    static var isDealer: Bool {
        UserDefaults.standard.bool(forKey: "ticklab.profile.isDealer")
    }
    static var photoData: Data? {
        UserDefaults.standard.data(forKey: "ticklab.profile.photoData")
    }
    static var startYear: String {
        UserDefaults.standard.string(forKey: "ticklab.profile.startYear") ?? ""
    }
    static var favoriteBrands: String {
        UserDefaults.standard.string(forKey: "ticklab.profile.brands") ?? ""
    }
    static var bio: String {
        UserDefaults.standard.string(forKey: "ticklab.profile.bio") ?? ""
    }
}
