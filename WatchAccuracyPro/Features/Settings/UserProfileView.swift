import PhotosUI
import SwiftUI

/// Sprint 10 (P3-13): 사용자 프로필 — UserDefaults 기반 로컬 저장.
/// CloudKit Phase 3에서 서버 동기화 예정.
struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var collectionStartYear: String = ""
    @State private var favoriteBrands: String = ""
    @State private var isDealerBadge: Bool = false
    @State private var bio: String = ""
    @State private var profilePhotoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var referralCode: String = ReferralService.referralCode

    private let nameKey = "ticklab.profile.name"
    private let yearKey = "ticklab.profile.startYear"
    private let brandsKey = "ticklab.profile.brands"
    private let dealerKey = "ticklab.profile.isDealer"
    private let bioKey = "ticklab.profile.bio"
    private let photoKey = "ticklab.profile.photoData"

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
                }

                Section(String(localized: "profile.section.collector")) {
                    HStack {
                        Text(String(localized: "profile.start_year"))
                        Spacer()
                        TextField("2020", text: $collectionStartYear)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    TextField(String(localized: "profile.fav_brands"), text: $favoriteBrands)
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
                    Button(String(localized: "common.save")) { save(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { load() }
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

    private func load() {
        let d = UserDefaults.standard
        displayName = d.string(forKey: nameKey) ?? ""
        collectionStartYear = d.string(forKey: yearKey) ?? ""
        favoriteBrands = d.string(forKey: brandsKey) ?? ""
        isDealerBadge = d.bool(forKey: dealerKey)
        bio = d.string(forKey: bioKey) ?? ""
        profilePhotoData = d.data(forKey: photoKey)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(displayName, forKey: nameKey)
        d.set(collectionStartYear, forKey: yearKey)
        d.set(favoriteBrands, forKey: brandsKey)
        d.set(isDealerBadge, forKey: dealerKey)
        d.set(bio, forKey: bioKey)
        d.set(profilePhotoData, forKey: photoKey)
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
}
