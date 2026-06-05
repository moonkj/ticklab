import PhotosUI
import SwiftData
import SwiftUI

/// Sprint 9 (P2-19): 드림 시계 위시리스트.
struct WishlistView: View {
    @Query(sort: \WishlistItem.createdAt, order: .reverse) private var items: [WishlistItem]
    @Environment(\.modelContext) private var context
    @State private var showingAdd = false
    @State private var editingItem: WishlistItem?

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyState(
                    icon: "heart",
                    title: String(localized: "wishlist.empty.title"),
                    message: String(localized: "wishlist.empty.body"),
                    cta: .init(label: String(localized: "wishlist.add")) { showingAdd = true }
                )
            } else {
                List {
                    ForEach(items) { item in
                        wishRow(item)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .onTapGesture { editingItem = item }
                    }
                    .onDelete { offsets in
                        offsets.forEach { context.delete(items[$0]) }
                        try? context.save()
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "wishlist.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { WishlistComposerView() }
        .sheet(item: $editingItem) { WishlistComposerView(existing: $0) }
    }

    private func wishRow(_ item: WishlistItem) -> some View {
        HStack(spacing: 14) {
            // 사진 / 이니셜
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(AppColors.paper2).frame(width: 64, height: 64)
                if let data = item.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(String(item.brand.prefix(2)).uppercased())
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(AppColors.ink2)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.brand)
                    .font(.system(size: 12)).foregroundStyle(AppColors.ink2)
                Text(item.model)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(AppColors.ink0)
                if let price = item.targetPrice {
                    let fmt = NumberFormatter()
                    let _ = { fmt.numberStyle = .currency; fmt.currencyCode = item.currency; fmt.maximumFractionDigits = 0 }()
                    HStack(spacing: 4) {
                        ConceptGlyph(systemName: "target", size: 13).foregroundStyle(AppColors.accentDark)
                        Text(fmt.string(from: NSDecimalNumber(decimal: price)) ?? "")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(AppColors.accentDark)
                    }
                }
                // 팀 토론: 저축 진행 트래커 — 게이지 + 예상 도달 시점(목표가·저축액 있을 때).
                if let progress = item.savingsProgress {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: progress).tint(AppColors.accentDark)
                            .frame(maxWidth: 180)
                        HStack(spacing: 6) {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColors.ink2)
                            if let months = item.monthsToGoal {
                                Text(String(format: NSLocalizedString("wishlist.months_to_goal", comment: ""), months))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.ink3)
                            } else if progress >= 1.0 {
                                Text(String(localized: "wishlist.goal_reached"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColors.success)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(AppColors.ink3)
        }
        .padding(12)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            // 위시 → 컬렉션 원탭 전환(필드 승계). 갖게 됐을 때.
            Button {
                convertToCollection(item)
            } label: {
                Label(String(localized: "wishlist.convert"), systemImage: "checkmark.seal")
            }
        }
    }

    /// 위시 항목을 보유 시계로 승격 — brand/model/ref/목표가/사진 승계 후 위시 삭제.
    private func convertToCollection(_ item: WishlistItem) {
        let watch = Watch(
            brand: item.brand,
            model: item.model,
            photoData: item.imageData,
            referenceNumber: item.referenceNumber,
            purchasePrice: item.targetPrice,
            purchaseCurrency: item.currency
        )
        context.insert(watch)
        context.delete(item)
        try? context.save()
    }
}

struct WishlistComposerView: View {
    var existing: WishlistItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var brand = ""
    @State private var model = ""
    @State private var refNo = ""
    @State private var priceText = ""
    @State private var currency = Locale.current.currency?.identifier ?? "KRW"
    @State private var note = ""
    @State private var savedText = ""
    @State private var monthlyText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showingBrandInputSheet = false
    @State private var brandInputText = ""
    @State private var modelSuggestions: [String] = []
    @State private var showModelSuggestions = false
    @State private var showTextFilterAlert = false

    private static let currencies = ["KRW", "USD", "EUR", "JPY", "GBP", "CHF"]

    // AddWatchView와 동일한 브랜드 목록
    private let popularBrands = [
        "A. Lange & Söhne", "Audemars Piguet", "Ball", "Bell & Ross", "Blancpain",
        "Breguet", "Breitling", "Bulgari", "Cartier", "Casio", "Chopard",
        "Christopher Ward", "Citizen", "F.P. Journe", "Girard-Perregaux",
        "Glashütte Original", "Grand Seiko", "Greubel Forsey", "Hamilton",
        "Hermès", "Hublot", "IWC", "Jaeger-LeCoultre", "Longines",
        "Maurice Lacroix", "MB&F", "Mido", "Montblanc", "Nomos", "Omega", "Oris",
        "Panerai", "Patek Philippe", "Piaget", "Rado", "Richard Mille",
        "Roger Dubuis", "Rolex", "Seiko", "Sinn", "Swatch", "TAG Heuer",
        "Tissot", "Tudor", "Ulysse Nardin", "Vacheron Constantin", "Zenith"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            if let data = imageData, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                ConceptGlyph(systemName: "photo", size: 26).frame(width: 44, height: 44)
                                    .background(AppColors.paper2).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text(String(localized: "wishlist.photo")).foregroundStyle(AppColors.accentDark)
                        }
                    }
                }
                Section(String(localized: "addwatch.section.required")) {
                    // 브랜드 — AddWatchView와 동일한 Menu 방식
                    HStack {
                        Text(String(localized: "addwatch.brand"))
                        Spacer()
                        Menu {
                            ForEach(popularBrands, id: \.self) { b in
                                Button {
                                    brand = b
                                    modelSuggestions = WatchModelSuggestionService.models(for: b)
                                    showModelSuggestions = !modelSuggestions.isEmpty
                                } label: {
                                    if brand == b {
                                        Label(b, systemImage: "checkmark")
                                    } else {
                                        Text(b)
                                    }
                                }
                            }
                            Divider()
                            Button {
                                showingBrandInputSheet = true
                            } label: {
                                Label(String(localized: "addwatch.brand.custom"), systemImage: "square.and.pencil")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(brand.isEmpty ? String(localized: "common.unspecified") : brand)
                                    .foregroundStyle(brand.isEmpty ? AppColors.ink3 : AppColors.ink0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.ink3)
                            }
                            .frame(minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                        }
                    }
                    // 모델 — 자동완성 드롭다운
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(String(localized: "addwatch.model"), text: $model)
                            .onChange(of: model) { _, _ in
                                modelSuggestions = WatchModelSuggestionService.suggestions(brand: brand, partialModel: model)
                                showModelSuggestions = !modelSuggestions.isEmpty && !model.isEmpty
                            }
                        if showModelSuggestions && !modelSuggestions.isEmpty {
                            Divider().padding(.top, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(modelSuggestions.prefix(8), id: \.self) { suggestion in
                                        Button(suggestion) {
                                            model = suggestion
                                            showModelSuggestions = false
                                        }
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(AppColors.accent50)
                                        .clipShape(Capsule())
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .alert(String(localized: "addwatch.brand.custom"), isPresented: $showingBrandInputSheet) {
                    TextField(String(localized: "addwatch.brand"), text: $brandInputText)
                        .textInputAutocapitalization(.words)
                    Button(String(localized: "common.cancel"), role: .cancel) { brandInputText = "" }
                    Button(String(localized: "common.ok")) {
                        let trimmed = brandInputText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { brand = trimmed }
                        brandInputText = ""
                    }
                } message: {
                    Text(String(localized: "addwatch.brand.custom.hint"))
                }
                Section(String(localized: "addwatch.section.optional")) {
                    TextField(String(localized: "addwatch.reference_no"), text: $refNo).autocorrectionDisabled()
                    HStack {
                        TextField(String(localized: "wishlist.target_price"), text: $priceText).keyboardType(.decimalPad)
                        Picker("", selection: $currency) {
                            ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).labelsHidden()
                    }
                    // 팀 토론: 저축 진행 트래커 입력(외부 시세 API 없음·수동).
                    TextField(String(localized: "wishlist.saved_amount"), text: $savedText).keyboardType(.decimalPad)
                    TextField(String(localized: "wishlist.monthly_goal"), text: $monthlyText).keyboardType(.decimalPad)
                    TextField(String(localized: "wishlist.note"), text: $note, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(existing == nil ? String(localized: "wishlist.add") : String(localized: "wishlist.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(String(localized: "common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) { save() }.fontWeight(.semibold)
                        .disabled(brand.trimmingCharacters(in: .whitespaces).isEmpty || model.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
            .alert(String(localized: "text.filter.blocked.title"), isPresented: $showTextFilterAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(String(localized: "text.filter.blocked.body")) }
            .onChange(of: photoItem) { _, new in
                guard let new else { return }
                Task {
                    if let raw = try? await new.loadTransferable(type: Data.self) {
                        await MainActor.run { imageData = EXIFStripper.strippedJPEG(from: raw) }
                    }
                }
            }
        }
    }

    private func loadExisting() {
        guard let e = existing else { return }
        brand = e.brand; model = e.model; refNo = e.referenceNumber ?? ""
        priceText = e.targetPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        currency = e.currency; note = e.note; imageData = e.imageData
        savedText = e.savedAmount > 0 ? NSDecimalNumber(decimal: e.savedAmount).stringValue : ""
        monthlyText = e.monthlyGoal.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }

    private func save() {
        // 욕설 등 부적절 텍스트 사전 필터(자유 입력 필드만 — 가격/통화 제외).
        let userTexts = [brand, model, refNo, note]
        if userTexts.contains(where: { CommunityTextModerator.containsProfanity($0) }) {
            showTextFilterAlert = true
            return
        }
        let item = existing ?? WishlistItem(brand: brand, model: model)
        item.brand = brand.trimmingCharacters(in: .whitespaces)
        item.model = model.trimmingCharacters(in: .whitespaces)
        item.referenceNumber = refNo.isEmpty ? nil : refNo
        item.targetPrice = Decimal(string: priceText.trimmingCharacters(in: .whitespaces))
        item.currency = currency; item.note = note; item.imageData = imageData
        item.savedAmount = Decimal(string: savedText.trimmingCharacters(in: .whitespaces)) ?? 0
        item.monthlyGoal = Decimal(string: monthlyText.trimmingCharacters(in: .whitespaces))
        if existing == nil { context.insert(item) }
        try? context.save(); dismiss()
    }
}
