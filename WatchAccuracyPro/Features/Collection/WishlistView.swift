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
                        Image(systemName: "target").font(.system(size: 10)).foregroundStyle(AppColors.accentDark)
                        Text(fmt.string(from: NSDecimalNumber(decimal: price)) ?? "")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(AppColors.accentDark)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(AppColors.ink3)
        }
        .padding(12)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?

    private static let currencies = ["KRW", "USD", "EUR", "JPY", "GBP", "CHF"]

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
                                Image(systemName: "photo").frame(width: 44, height: 44)
                                    .background(AppColors.paper2).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text(String(localized: "wishlist.photo")).foregroundStyle(AppColors.accentDark)
                        }
                    }
                }
                Section(String(localized: "addwatch.section.required")) {
                    TextField(String(localized: "addwatch.brand"), text: $brand)
                    TextField(String(localized: "addwatch.model"), text: $model)
                }
                Section(String(localized: "addwatch.section.optional")) {
                    TextField(String(localized: "addwatch.reference_no"), text: $refNo).autocorrectionDisabled()
                    HStack {
                        TextField(String(localized: "wishlist.target_price"), text: $priceText).keyboardType(.decimalPad)
                        Picker("", selection: $currency) {
                            ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).labelsHidden()
                    }
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
    }

    private func save() {
        let item = existing ?? WishlistItem(brand: brand, model: model)
        item.brand = brand.trimmingCharacters(in: .whitespaces)
        item.model = model.trimmingCharacters(in: .whitespaces)
        item.referenceNumber = refNo.isEmpty ? nil : refNo
        item.targetPrice = Decimal(string: priceText.trimmingCharacters(in: .whitespaces))
        item.currency = currency; item.note = note; item.imageData = imageData
        if existing == nil { context.insert(item) }
        try? context.save(); dismiss()
    }
}
