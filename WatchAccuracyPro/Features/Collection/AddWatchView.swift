import SwiftUI
import SwiftData
import PhotosUI

struct AddWatchView: View {
    /// Round 173: 기존 시계 수정 지원. nil 이면 신규 추가, 값 있으면 편집 모드.
    var existing: Watch? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var caliber: String? = nil
    @State private var purchaseDate: Date? = nil
    /// Round 83 (정수민): 별명 / story / ref no. 감성 필드.
    @State private var nickname: String = ""
    @State private var story: String = ""
    @State private var referenceNumber: String = ""
    @State private var receivedFrom: String = ""
    /// Sprint 1 (P3-5): 구매처/담당자 — 자유 텍스트, optional.
    @State private var purchaseLocation: String = ""
    @State private var purchaseSalesperson: String = ""
    /// Sprint 1 (P3-4): 구매가 + 통화. 빈 문자열 = nil.
    @State private var purchasePriceText: String = ""
    @State private var purchaseCurrency: String = Locale.current.currency?.identifier ?? "USD"
    /// 구매 컨디션(새상품/미착용/중고) + 연식.
    @State private var purchaseCondition: PurchaseCondition? = nil
    @State private var productionYearText: String = ""
    /// Sprint 2 (P2-9): 보증 기간 (개월). 0 = 미설정.
    @State private var warrantyMonths: Int = 0
    @State private var warrantyReminderEnabled: Bool = true
    /// Sprint 4 (P1-5): 선택 항목 펼치기/접기.
    @State private var optionalExpanded: Bool = false
    /// Sprint 5 (P2-2): 모델 자동완성.
    @State private var modelSuggestions: [String] = []
    @State private var showModelSuggestions: Bool = false
    /// T-07: 브랜드 자동완성 (무브먼트 DB brandFamilies 기반).
    ///   2글자 이상 입력 시 ~300ms 디바운스 후 검색. 탭 시 채움.
    @State private var brandSuggestions: [String] = []
    @State private var showBrandSuggestions: Bool = false
    @State private var brandSearchTask: Task<Void, Never>? = nil
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var cropPayload: CropImagePayload?
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var showingPhotoSourceDialog = false
    @State private var showingDiscardAlert = false
    /// 욕설 등 금칙어 포함 시 저장 차단 alert (커뮤니티 캡션 필터와 동일 정책).
    @State private var showTextFilterAlert = false
    @State private var suggestion: MovementMatcher.Suggestion?
    /// 페르소나 (김재철, 워치메이커) wish: lift angle override.
    @State private var liftAngleOverride: String = ""
    /// 무브먼트 직접입력 BPH (caliber == Watch.manualCaliberTag 일 때).
    @State private var manualBphText: String = ""
    @State private var showingBrandInputSheet: Bool = false
    @State private var brandInputText: String = ""
    /// Round (1-3 사용자 요청): 200+ Picker → searchable sheet.
    @State private var showingMovementPicker: Bool = false
    /// Round 2-3: sentinel 은 Watch.manualCaliberTag 로 통일. local alias 만 유지 (가독성).
    private var isManualEntry: Bool { caliber == Watch.manualCaliberTag }
    /// 무브먼트 타입 — automatic / manual / quartz.
    @State private var movementType: WatchMovementType = .automatic
    /// 수동감기: 매일 알림 활성화 + 시각.
    @State private var windReminderEnabled: Bool = false
    @State private var windReminderTime: Date = {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }()
    /// Quartz: 마지막 배터리 교체일 + 알림.
    @State private var batteryLastReplaced: Date = Date()
    @State private var batteryReminderEnabled: Bool = true
    /// 스마트워치: 완충 시 배터리 지속일(일). 경과시간으로 % 표시.
    @State private var batteryFullChargeDays: Int = 2
    @Environment(UserPreferences.self) private var preferences

    private var isEditing: Bool { existing != nil }

    private let matcher = MovementMatcher()
    /// Round 84-87 (사용자 피드백 누적): 브랜드 풀 대폭 확장.
    /// 알파벳 순. 입문 / 빈티지 / 하이엔드 / haute horlogerie / 패션 브랜드까지 포괄.
    /// 사용자가 못 찾으면 "addwatch.brand.custom" 자유 입력 가능.
    private let popularBrands = [
        "A. Lange & Söhne", "Amazfit", "Anonimo", "Apple", "Aquastar", "Audemars Piguet", "Ball",
        "Bell & Ross", "Blancpain", "Breguet", "Breitling", "Bremont", "Bulgari", "Bulova",
        "Carl F. Bucherer", "Cartier", "Casio", "Chanel", "Chopard", "Christopher Ward",
        "Citizen", "Czapek", "De Bethune", "Dior", "Doxa", "Eterna", "Fitbit", "Fortis",
        "F.P. Journe", "Franck Muller", "Frederique Constant", "Garmin", "Girard-Perregaux",
        "Glashütte Original", "Google", "Grand Seiko", "Greubel Forsey", "H. Moser & Cie",
        "Hamilton", "Hermès", "Huawei", "Hublot", "IWC", "Jacob & Co", "Jaeger-LeCoultre",
        "Junghans", "Laurent Ferrier", "Longines", "Louis Vuitton", "MB&F",
        "Maurice Lacroix", "Mido", "Montblanc", "Movado", "Nomos", "Omega", "Oris",
        "Panerai", "Parmigiani Fleurier", "Patek Philippe", "Piaget", "Polar", "Rado", "Ressence",
        "Richard Mille", "Roger Dubuis", "Rolex", "Samsung", "Seiko", "Sinn", "Suunto", "Swatch",
        "TAG Heuer", "Tissot", "Tudor", "Tutima", "Ulysse Nardin", "Universal Genève", "Urwerk",
        "Vacheron Constantin", "Van Cleef & Arpels", "Withings", "Xiaomi", "Zenith"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "addwatch.section.photo")) {
                    photoPicker
                }
                // Sprint 4 (P1-5): 필수 항목 레이블
                Section(header: Text(String(localized: "addwatch.section.required"))) {
                    // 브랜드: 직접 타이핑(자동완성) + Menu 인기목록 선택을 한 행에서.
                    //   TextField 로 자유 입력 → 무브먼트 DB brandFamilies 매칭 dropdown 표시 (T-07).
                    //   Menu(chevron) 는 기존 인기 브랜드 / 직접 입력 시트 흐름 유지.
                    // 브랜드 — Menu 선택(드림위시리스트와 동일 방식). 인기목록 + 직접 입력.
                    HStack {
                        Text(String(localized: "addwatch.brand"))
                        Spacer()
                        Menu {
                            ForEach(popularBrands, id: \.self) { b in
                                Button { brand = b } label: {
                                    if brand == b { Label(b, systemImage: "checkmark") } else { Text(b) }
                                }
                            }
                            Divider()
                            Button { showingBrandInputSheet = true } label: {
                                Label(String(localized: "addwatch.brand.custom"), systemImage: "square.and.pencil")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(brand.isEmpty ? String(localized: "common.unspecified") : brand)
                                    .foregroundStyle(brand.isEmpty ? AppColors.ink3 : AppColors.ink0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11)).foregroundStyle(AppColors.ink3)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        TextField(String(localized: "addwatch.model"), text: $model)
                            .onChange(of: model) { _, _ in
                                updateSuggestion()
                                // Sprint 5 (P2-2): 모델 자동완성
                                modelSuggestions = WatchModelSuggestionService.suggestions(
                                    brand: brand, partialModel: model
                                )
                                showModelSuggestions = !modelSuggestions.isEmpty && !model.isEmpty
                            }
                            .onChange(of: brand) { _, newBrand in
                                // 브랜드 변경 시 해당 브랜드 모델 목록 표시
                                modelSuggestions = WatchModelSuggestionService.models(for: newBrand)
                                showModelSuggestions = !modelSuggestions.isEmpty && model.isEmpty
                            }
                        if showModelSuggestions {
                            Divider().padding(.top, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(modelSuggestions.prefix(8), id: \.self) { suggestion in
                                        Button(suggestion) {
                                            model = suggestion
                                            showModelSuggestions = false
                                            updateSuggestion()
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

                // Sprint 4 (P1-5): 선택 항목 DisclosureGroup
                Section {
                    DisclosureGroup(
                        isExpanded: $optionalExpanded,
                        content: {
                            DatePicker(
                                String(localized: "addwatch.purchase_date"),
                                selection: Binding(
                                    get: { purchaseDate ?? Date() },
                                    set: { purchaseDate = $0 }
                                ),
                                displayedComponents: .date
                            )
                            .padding(.leading, 4)
                        },
                        label: {
                            Text(String(localized: "addwatch.section.optional"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.accentDark)
                        }
                    )
                }

                Section(String(localized: "addwatch.movement.type")) {
                    // 스마트워치 추가로 5개 → 세그먼트가 짤림. 칩 그리드(2줄 자동 줄바꿈).
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(WatchMovementType.allCases, id: \.self) { t in
                            Button { movementType = t } label: {
                                Text(t.displayName)
                                    .font(.system(size: 14, weight: movementType == t ? .semibold : .regular))
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                    .foregroundStyle(movementType == t ? AppColors.paper0 : AppColors.ink1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(movementType == t ? AppColors.accent : AppColors.paper1)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9)
                                        .stroke(movementType == t ? Color.clear : AppColors.rule, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    if movementType == .manual {
                        Toggle(String(localized: "addwatch.wind.toggle"), isOn: $windReminderEnabled)
                        if windReminderEnabled {
                            DatePicker(String(localized: "addwatch.wind.time"),
                                       selection: $windReminderTime,
                                       displayedComponents: .hourAndMinute)
                        }
                        Text(String(localized: "addwatch.movement.manual.hint"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if movementType == .quartz {
                        DatePicker(String(localized: "addwatch.battery.last_replaced"),
                                   selection: $batteryLastReplaced,
                                   displayedComponents: .date)
                        Toggle(String(localized: "addwatch.battery.reminder.toggle"), isOn: $batteryReminderEnabled)
                        Text(String(localized: "addwatch.movement.quartz.hint"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                // 스마트워치: 무브먼트(캘리버) 항목 숨김 + 배터리 지속일 입력.
                if movementType == .smartwatch {
                    Section(String(localized: "addwatch.battery.section")) {
                        Stepper(value: $batteryFullChargeDays, in: 1...30) {
                            HStack {
                                ConceptGlyph(systemName: "battery.100", size: 17).foregroundStyle(AppColors.success)
                                Text(String(localized: "addwatch.battery.life_days"))
                                Spacer()
                                Text(String(format: String(localized: "addwatch.battery.days_value"), batteryFullChargeDays))
                                    .foregroundStyle(AppColors.ink2)
                            }
                        }
                        Text(String(localized: "addwatch.battery.hint"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                if movementType != .smartwatch {
                Section(String(localized: "addwatch.section.movement")) {
                    if let suggestion, caliber == nil {
                        suggestionCard(suggestion)
                    }
                    // 페르소나 (김재철) wish: expert 모드에서만 lift angle override 입력.
                    if preferences.userMode == .pro {
                        HStack {
                            Text(String(localized: "addwatch.lift_angle.label"))
                            Spacer()
                            TextField(String(localized: "addwatch.lift_angle.placeholder"),
                                      text: $liftAngleOverride)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                    // Round (1-3): 200+ ForEach Picker → searchable sheet 로 교체.
                    //   사용자가 brand 입력한 상태면 brand 매칭 무브먼트가 상단 추천 섹션.
                    Button {
                        showingMovementPicker = true
                    } label: {
                        HStack {
                            Text(String(localized: "addwatch.movement.picker"))
                                .foregroundStyle(AppColors.ink0)
                            Spacer()
                            Text(caliberDisplayLabel())
                                .foregroundStyle(caliber == nil ? AppColors.ink3 : AppColors.ink2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.ink3)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // 직접입력 선택 시 BPH 입력 필드 (측정에 필수)
                    if isManualEntry {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "addwatch.movement.bph_label"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                    HStack(spacing: 6) {
                                        TextField("28800", text: $manualBphText)
                                            .keyboardType(.numberPad)
                                            .font(.system(size: 17, design: .monospaced))
                                        Text(String(localized: "watch.spec.bph"))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                                Spacer()
                                if let bph = Int(manualBphText), bph > 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColors.success)
                                }
                            }
                            if manualBphText.isEmpty {
                                Label(String(localized: "addwatch.movement.bph_required"), systemImage: "exclamationmark.circle.fill")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.warning)
                            } else if let bph = Int(manualBphText), bph > 0 {
                                let commonBPHs = [18000, 21600, 25200, 28800, 36000]
                                if !commonBPHs.contains(bph) {
                                    Label(String(format: NSLocalizedString("addwatch.movement.bph_uncommon", comment: ""), bph),
                                          systemImage: "info.circle")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.ink3)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if let caliber, let movement = MovementDatabase.shared.movement(id: caliber) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(movement.id)
                                    .font(AppTypography.headline)
                                Text("\(movement.bph) \(String(localized: "watch.spec.bph")) · \(Int(movement.liftAngleDegrees))° · \(movement.escapement.rawValue)")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
                }   // if movementType != .smartwatch

                // Round 83 (정수민/이재현): personalisation 섹션 — 별명/스토리/ref no.
                Section(String(localized: "addwatch.section.personal")) {
                    TextField(String(localized: "addwatch.nickname"), text: $nickname)
                    TextField(String(localized: "addwatch.reference_no"), text: $referenceNumber)
                        .autocorrectionDisabled()
                    // Sprint 13 (F2): 증여자/전승 (선택).
                    TextField(String(localized: "addwatch.received_from"), text: $receivedFrom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "addwatch.story.label"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                        TextField(String(localized: "addwatch.story.placeholder"), text: $story, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }

                Section(String(localized: "addwatch.section.purchase")) {
                    TextField(String(localized: "addwatch.purchase.location"), text: $purchaseLocation)
                    TextField(String(localized: "addwatch.purchase.salesperson"), text: $purchaseSalesperson)
                    HStack {
                        TextField(String(localized: "addwatch.purchase.price"), text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                        Picker("", selection: $purchaseCurrency) {
                            Text("KRW").tag("KRW")
                            Text("USD").tag("USD")
                            Text("EUR").tag("EUR")
                            Text("JPY").tag("JPY")
                            Text("GBP").tag("GBP")
                            Text("CHF").tag("CHF")
                            Text("CNY").tag("CNY")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    Text(String(localized: "addwatch.purchase.price.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink3)
                    // 구매 컨디션(새상품/미착용/중고) — 가격 집계·유추 입력. TODO(phase2): 서버 집계 그래프.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "addwatch.condition.label"))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(AppColors.ink2)
                        HStack(spacing: 8) {
                            ForEach(PurchaseCondition.allCases, id: \.self) { c in
                                Button { purchaseCondition = (purchaseCondition == c) ? nil : c } label: {
                                    Text(c.displayName)
                                        .font(.system(size: 13, weight: purchaseCondition == c ? .semibold : .regular))
                                        .lineLimit(1).minimumScaleFactor(0.85)
                                        .foregroundStyle(purchaseCondition == c ? AppColors.paper0 : AppColors.ink1)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(purchaseCondition == c ? AppColors.accent : AppColors.paper1)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(purchaseCondition == c ? Color.clear : AppColors.rule, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        Text(String(localized: "addwatch.production_year"))
                        Spacer()
                        TextField("2020", text: $productionYearText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    // Sprint 2 (P2-9): 보증 기간 + 알림.
                    Picker(String(localized: "addwatch.warranty.months"), selection: $warrantyMonths) {
                        Text(String(localized: "addwatch.warranty.none")).tag(0)
                        Text(String(localized: "addwatch.warranty.12m")).tag(12)
                        Text(String(localized: "addwatch.warranty.24m")).tag(24)
                        Text(String(localized: "addwatch.warranty.36m")).tag(36)
                        Text(String(localized: "addwatch.warranty.48m")).tag(48)
                        Text(String(localized: "addwatch.warranty.60m")).tag(60)
                        Text(String(localized: "addwatch.warranty.72m")).tag(72)
                        Text(String(localized: "addwatch.warranty.84m")).tag(84)
                        Text(String(localized: "addwatch.warranty.96m")).tag(96)
                        Text(String(localized: "addwatch.warranty.108m")).tag(108)
                        Text(String(localized: "addwatch.warranty.120m")).tag(120)
                    }
                    if warrantyMonths > 0 {
                        Toggle(String(localized: "addwatch.warranty.reminder"),
                               isOn: $warrantyReminderEnabled)
                    }
                }

                // Round 84: 디자인 SSOT screens-detail.jsx AddWatchView 시리얼 안내 helpcard.
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppColors.info)
                        Text(String(localized: "addwatch.serial.hint"))
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.ink1)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppColors.info.opacity(0.08))
            }
            .navigationTitle(isEditing
                             ? String(localized: "editwatch.title")
                             : String(localized: "addwatch.title"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(String(localized: "addwatch.brand.custom"), isPresented: $showingBrandInputSheet) {
                TextField(String(localized: "addwatch.brand"), text: $brandInputText)
                    .textInputAutocapitalization(.words)
                Button(String(localized: "common.cancel"), role: .cancel) {
                    brandInputText = ""
                }
                Button(String(localized: "common.ok")) {
                    let trimmed = brandInputText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        brand = trimmed
                        updateSuggestion()
                    }
                    brandInputText = ""
                }
            } message: {
                Text(String(localized: "addwatch.brand.custom.hint"))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        // Round 170: 미저장 변경 확인 — 데이터 손실 방지.
                        if hasUnsavedChanges {
                            showingDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .alert(String(localized: "addwatch.discard.title"),
                   isPresented: $showingDiscardAlert) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "addwatch.discard.confirm"), role: .destructive) { dismiss() }
            } message: {
                Text(String(localized: "addwatch.discard.message"))
            }
            .alert(String(localized: "text.filter.blocked.title"), isPresented: $showTextFilterAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "text.filter.blocked.body"))
            }
            .onAppear { loadExisting() }
        }
    }

    /// Round 173: 편집 모드 진입 시 기존 시계 데이터를 state 로 복원.
    private func loadExisting() {
        guard let existing else { return }
        // Sprint 4 (P1-5): 편집 모드에서는 선택 항목 자동 펼침.
        optionalExpanded = true
        brand = existing.brand
        model = existing.model
        caliber = existing.caliber
        purchaseDate = existing.purchaseDate
        photoData = existing.photoData
        liftAngleOverride = existing.liftAngleOverride.map { String(format: "%.0f", $0) } ?? ""
        movementType = existing.movementType
        batteryFullChargeDays = Int(existing.batteryFullChargeDays ?? 2)
        windReminderEnabled = existing.windReminderEnabled
        // 0:00 (자정) 도 유효한 시각 — guard 제거.
        windReminderTime = Calendar.current.date(
            bySettingHour: existing.windReminderHour,
            minute: existing.windReminderMinute,
            second: 0, of: Date()
        ) ?? windReminderTime
        batteryLastReplaced = existing.batteryLastReplaced ?? Date()
        batteryReminderEnabled = existing.batteryReminderEnabled
        nickname = existing.nickname ?? ""
        story = existing.story ?? ""
        receivedFrom = existing.receivedFrom ?? ""
        referenceNumber = existing.referenceNumber ?? ""
        purchaseLocation = existing.purchaseLocation ?? ""
        purchaseSalesperson = existing.purchaseSalesperson ?? ""
        purchasePriceText = existing.purchasePrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        purchaseCurrency = existing.purchaseCurrency ?? purchaseCurrency
        purchaseCondition = existing.purchaseCondition
        productionYearText = existing.productionYear.map(String.init) ?? ""
        warrantyMonths = existing.warrantyMonths ?? 0
        warrantyReminderEnabled = existing.warrantyReminderEnabled
        if let bph = existing.customBph { manualBphText = String(bph) }
    }

    /// Round 88: photo 없으면 brand+model 기반 WatchSilhouette 미리보기 (즉시 시각 피드백).
    private var photoPicker: some View {
        HStack(spacing: 12) {
            ZStack {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else if !brand.isEmpty || !model.isEmpty {
                    // Brand/model 입력 중이면 실시간 silhouette preview.
                    WatchSilhouette(
                        model: silhouetteModelKey(model: model),
                        tone: silhouetteToneKey(brand: brand),
                        size: 60
                    )
                } else {
                    ConceptGlyph(systemName: "photo", size: 30)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .frame(width: 72, height: 72)
            .background(AppColors.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showingPhotoSourceDialog = true
                } label: {
                    Label(
                        String(localized: photoData != nil ? "addwatch.replace_photo" : "addwatch.choose_photo"),
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.system(size: 14))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accent)
                if photoData != nil {
                    Button(role: .destructive) {
                        photoData = nil
                        photoItem = nil
                    } label: {
                        Label(String(localized: "addwatch.remove_photo"), systemImage: "trash")
                            .font(.system(size: 13))
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.danger)
                }
            }
        }
        // Round 170 (사용자 보고: 사진 선택 / 사진 찍기 분리 안되고 순차 노출 버그):
        // 두 개의 별도 tappable view → 단일 confirmation dialog 로 통합. 사용자가 선택 후 해당 sheet 만 표시.
        .confirmationDialog(
            String(localized: "addwatch.photo_source.title"),
            isPresented: $showingPhotoSourceDialog,
            titleVisibility: .visible
        ) {
            Button(String(localized: "addwatch.photo_source.library")) {
                showingPhotosPicker = true
            }
            Button(String(localized: "addwatch.photo_source.camera")) {
                showingCamera = true
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPhotosPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            // 사용자 요청: 업로드 시 4:3 크롭으로 프레임 맞춤 → 표시(4:3)와 일치, 잘림 없음.
            Task {
                guard let raw = try? await item?.loadTransferable(type: Data.self),
                      let ui = UIImage(data: raw) else { return }
                await MainActor.run { cropPayload = CropImagePayload(image: ui) }
            }
        }
        .sheet(isPresented: $showingCamera) {
            // 카메라 촬영도 동일하게 크롭 단계 경유.
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
                onComplete: { cropped in
                    // EXIF strip 은 detached 부담이 작아 동기 처리 (크롭 결과는 이미 metadata 없음).
                    photoData = EXIFStripper.strippedJPEG(from: cropped)
                    cropPayload = nil
                },
                onCancel: { cropPayload = nil }
            )
        }
        .sheet(isPresented: $showingMovementPicker) {
            MovementPickerSheet(
                selectedCaliber: Binding(
                    get: { caliber },
                    set: { caliber = $0 }
                ),
                manualEntryTag: Watch.manualCaliberTag,
                brandHint: brand
            )
            .presentationDetents([.large])
        }
    }

    /// Round (1-3): 무브먼트 picker button 의 우측 라벨 — 선택 상태 표시.
    private func caliberDisplayLabel() -> String {
        switch caliber {
        case .none:
            return String(localized: "addwatch.movement.unknown")
        case .some(Watch.manualCaliberTag):
            return String(localized: "addwatch.movement.manual_entry")
        case .some(let id):
            return id
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
        guard !brand.trimmingCharacters(in: .whitespaces).isEmpty,
              !model.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        // 직접입력 선택 시 유효한 BPH 입력 필수.
        if isManualEntry {
            guard let bph = Int(manualBphText), bph > 0 else { return false }
        }
        return true
    }

    /// Round 170: 미저장 변경 감지 — cancel 시 데이터 손실 확인.
    private var hasUnsavedChanges: Bool {
        if isEditing { return false }  // 편집 모드는 매번 alert 보일 필요 없음.
        return !brand.isEmpty || !model.isEmpty || photoData != nil
            || !nickname.isEmpty || !story.isEmpty || !referenceNumber.isEmpty
            || !purchaseLocation.isEmpty || !purchaseSalesperson.isEmpty
            || !purchasePriceText.isEmpty
            || caliber != nil
    }

    /// Brand string → silhouette tone key (Watch.silhouetteTone 와 유사하나 form input 기반).
    private func silhouetteToneKey(brand: String) -> String {
        let b = brand.lowercased()
        if b.contains("rolex") { return "green" }
        if b.contains("omega") { return "silver" }
        if b.contains("tudor") { return "black" }
        if b.contains("cartier") { return "gold" }
        if b.contains("jaeger") { return "gold" }
        if b.contains("iwc") { return "silver" }
        if b.contains("patek") { return "blue" }
        if b.contains("audemars") { return "silver" }
        if b.contains("seiko") { return "silver" }
        return "gold"
    }

    /// Model string → silhouette model key.
    private func silhouetteModelKey(model: String) -> String {
        let m = model.lowercased()
        if m.contains("speed") || m.contains("chrono") { return "speedmaster" }
        if m.contains("sub") { return "submariner" }
        if m.contains("gmt") { return "gmt" }
        if m.contains("date") { return "datejust" }
        if m.contains("tank") { return "tank" }
        if m.contains("reverso") { return "reverso" }
        return "submariner"
    }

    private func updateSuggestion() {
        suggestion = matcher.suggest(brand: brand, model: model)
    }

    /// T-07: 브랜드 입력 디바운스 검색.
    ///   2글자 미만이면 dropdown 숨김. 이상이면 ~300ms 후 무브먼트 DB brandFamilies 매칭.
    private func scheduleBrandSearch() {
        brandSearchTask?.cancel()
        let query = brand.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            brandSuggestions = []
            showBrandSuggestions = false
            return
        }
        brandSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms 디바운스.
            if Task.isCancelled { return }
            let results = MovementDatabase.searchBrands(query)
            await MainActor.run {
                // 입력값과 정확히 같은 단일 결과면 dropdown 불필요 (이미 채워진 상태).
                if results.count == 1, results[0].lowercased() == query.lowercased() {
                    brandSuggestions = []
                    showBrandSuggestions = false
                } else {
                    brandSuggestions = results
                    showBrandSuggestions = !results.isEmpty
                }
            }
        }
    }

    /// T-07: dropdown / Menu 에서 브랜드 확정 — 필드 채우고 dropdown 닫음.
    private func selectBrand(_ value: String) {
        brandSearchTask?.cancel()
        brand = value
        brandSuggestions = []
        showBrandSuggestions = false
        updateSuggestion()
    }

    private func save() {
        // 욕설 등 금칙어 필터 — 자유 텍스트(프로즈) 필드만 검사. 저장 전 차단.
        //   숫자(가격/lift/BPH)·통화 picker·시리얼(Keychain 별도)은 제외.
        let userTexts = [brand, model, nickname, story, referenceNumber,
                         receivedFrom, purchaseLocation, purchaseSalesperson]
        if userTexts.contains(where: { CommunityTextModerator.containsProfanity($0) }) {
            showTextFilterAlert = true
            return  // 저장 차단 — 시트 유지.
        }
        // Round 112 (데이터 무결성 H-2): quartz + 기계식 caliber 불일치 → caliber 자동 초기화.
        if movementType == .quartz, let cal = caliber,
           let m = MovementDatabase.shared.movement(id: cal),
           m.escapement != .quartz {
            caliber = nil  // quartz 시계에 기계식 caliber 부착 차단.
        }
        // Round 173: 편집 모드면 기존 watch 의 필드만 업데이트, 신규면 새 Watch 생성.
        let watch: Watch
        let nicknameTrimmed = nickname.trimmingCharacters(in: .whitespaces)
        let storyTrimmed = story.trimmingCharacters(in: .whitespaces)
        let refTrimmed = referenceNumber.trimmingCharacters(in: .whitespaces)
        let purchaseLocationTrimmed = purchaseLocation.trimmingCharacters(in: .whitespaces)
        let purchaseSalespersonTrimmed = purchaseSalesperson.trimmingCharacters(in: .whitespaces)
        let purchasePriceTrimmed = purchasePriceText.trimmingCharacters(in: .whitespaces)
        let parsedPurchasePrice: Decimal? = Decimal(string: purchasePriceTrimmed)
        let receivedFromTrimmed = receivedFrom.trimmingCharacters(in: .whitespaces)
        let parsedCustomBph: Int? = isManualEntry ? Int(manualBphText) : nil
        if let existing {
            existing.brand = brand
            existing.model = model
            existing.caliber = caliber
            existing.purchaseDate = purchaseDate
            existing.photoData = photoData
            PhotoCache.invalidate(id: existing.id)
            // Round (3-1): 다음 ListRow/Hero render 시 main thread 디코드 spike 회피.
            PhotoCache.prefetch(for: existing.id, data: photoData)
            existing.liftAngleOverride = Double(liftAngleOverride.trimmingCharacters(in: .whitespaces))
            existing.movementType = movementType
            existing.nickname = nicknameTrimmed.isEmpty ? nil : nicknameTrimmed
            existing.story = storyTrimmed.isEmpty ? nil : storyTrimmed
            existing.referenceNumber = refTrimmed.isEmpty ? nil : refTrimmed
            existing.receivedFrom = receivedFromTrimmed.isEmpty ? nil : receivedFromTrimmed
            existing.purchaseLocation = purchaseLocationTrimmed.isEmpty ? nil : purchaseLocationTrimmed
            existing.purchaseSalesperson = purchaseSalespersonTrimmed.isEmpty ? nil : purchaseSalespersonTrimmed
            existing.purchasePrice = parsedPurchasePrice
            existing.purchaseCurrency = parsedPurchasePrice != nil ? purchaseCurrency : nil
            existing.warrantyMonths = warrantyMonths > 0 ? warrantyMonths : nil
            existing.warrantyReminderEnabled = warrantyReminderEnabled
            existing.customBph = parsedCustomBph
            watch = existing
        } else {
            watch = Watch(
                brand: brand,
                model: model,
                caliber: caliber,
                purchaseDate: purchaseDate,
                photoData: photoData,
                liftAngleOverride: Double(liftAngleOverride.trimmingCharacters(in: .whitespaces)),
                movementType: movementType,
                nickname: nicknameTrimmed.isEmpty ? nil : nicknameTrimmed,
                story: storyTrimmed.isEmpty ? nil : storyTrimmed,
                referenceNumber: refTrimmed.isEmpty ? nil : refTrimmed,
                purchaseLocation: purchaseLocationTrimmed.isEmpty ? nil : purchaseLocationTrimmed,
                purchaseSalesperson: purchaseSalespersonTrimmed.isEmpty ? nil : purchaseSalespersonTrimmed,
                purchasePrice: parsedPurchasePrice,
                purchaseCurrency: parsedPurchasePrice != nil ? purchaseCurrency : nil,
                warrantyMonths: warrantyMonths > 0 ? warrantyMonths : nil,
                warrantyReminderEnabled: warrantyReminderEnabled,
                receivedFrom: receivedFromTrimmed.isEmpty ? nil : receivedFromTrimmed
            )
            watch.customBph = parsedCustomBph
            modelContext.insert(watch)
            // Round (3-1): 신규 시계도 prefetch.
            PhotoCache.prefetch(for: watch.id, data: photoData)
        }
        // 구매 컨디션 + 연식 (신규/편집 공통).
        watch.purchaseCondition = purchaseCondition
        watch.productionYear = Int(productionYearText.trimmingCharacters(in: .whitespaces))
        if movementType == .manual {
            watch.windReminderEnabled = windReminderEnabled
            let comps = Calendar.current.dateComponents([.hour, .minute], from: windReminderTime)
            watch.windReminderHour = comps.hour ?? 9
            watch.windReminderMinute = comps.minute ?? 0
        } else {
            // 타입이 manual 이 아니면 wind reminder 끔.
            watch.windReminderEnabled = false
            NotificationService.cancelWindReminder(for: watch)
        }
        if movementType == .quartz {
            watch.batteryLastReplaced = batteryLastReplaced
            watch.batteryReminderEnabled = batteryReminderEnabled
        } else {
            watch.batteryReminderEnabled = false
            NotificationService.cancelBatteryReminder(for: watch)
        }
        // 스마트워치: 완충 지속일 저장. 신규/완충일 없으면 지금 완충 가정. 캘리버는 의미 없으니 제거.
        if movementType == .smartwatch {
            watch.batteryFullChargeDays = Double(batteryFullChargeDays)
            if watch.batteryChargedAt == nil { watch.batteryChargedAt = Date() }
            watch.caliber = nil
        } else {
            watch.batteryFullChargeDays = nil
            watch.batteryChargedAt = nil
        }
        try? modelContext.save()

        if movementType == .manual && watch.windReminderEnabled {
            NotificationService.scheduleWindReminder(for: watch)
        }
        if movementType == .quartz && watch.batteryReminderEnabled {
            NotificationService.scheduleBatteryReminder(for: watch)
        }
        // Sprint 2 (P2-9): 보증 알림 — purchaseDate + warrantyMonths 둘 다 있으면 schedule.
        NotificationService.scheduleWarrantyReminder(for: watch)
        // 사용자 요청: 시계 추가/편집 시 오버홀 리마인더도 같이 스케줄.
        //   기계식 (auto/manual) 만 대상 — quartz·스마트워치는 오버홀 개념 없음(제외).
        if movementType != .quartz && movementType != .smartwatch {
            let lastDate = NotificationService.lastOverhaulDate(for: watch, in: modelContext) ?? watch.createdAt
            NotificationService.scheduleOverhaulReminder(
                for: watch,
                lastOverhaulDate: lastDate,
                years: preferences.overhaulReminderYears,
                enabled: preferences.overhaulReminderEnabled
            )
        }
        // 캐시 무효화 — 모델 변경이 collection / detail 에 즉시 반영.
        WatchMoodService.invalidate(for: watch)
        dismiss()
    }
}

#Preview {
    AddWatchView()
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
