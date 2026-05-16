import PhotosUI
import SwiftUI
import UIKit

/// 공유 카드 composer — 사진 full-bleed + 텍스트 overlay.
/// 스타일·배경 피커 제거. 비율, 사진 소스, 표시 옵션(측정값/날짜/본문)만 제공.
struct ShareCardComposerView: View {
    let entry: JournalEntry?
    let directWatch: Watch?
    let directMeasurement: WatchMeasurement?
    let directRate: Double?
    let entryPhotoData: Data?

    @Environment(\.dismiss) private var dismiss

    init(entry: JournalEntry?, watch: Watch? = nil, measurement: WatchMeasurement? = nil,
         directRate: Double? = nil, entryPhotoData: Data? = nil) {
        self.entry = entry
        self.directWatch = watch
        self.directMeasurement = measurement
        self.directRate = directRate
        self.entryPhotoData = entryPhotoData
    }

    // MARK: - Derived

    private var effectiveWatch: Watch? { entry?.watch ?? directWatch }

    /// measurement lookup: entry → direct → watch 최신 순 fallback.
    private var effectiveMeasurement: WatchMeasurement? {
        if let mid = entry?.measurementId,
           let m = entry?.watch?.measurements.first(where: { $0.id == mid }) { return m }
        if let dm = directMeasurement { return dm }
        return effectiveWatch?.measurements.max(by: { $0.timestamp < $1.timestamp })
    }

    @MainActor private var rateString: String {
        let rate: Double
        if let m = effectiveMeasurement { rate = m.rateSecondsPerDay }
        else if let r = directRate { rate = r }
        else { return "—" }
        return (rate >= 0 ? "+" : "") + String(format: "%.1f", rate)
    }

    private var dateString: String {
        let date = effectiveMeasurement?.timestamp ?? entry?.timestamp ?? Date()
        return AppDateFormat.fullDate(date)
    }

    private var captionText: String? {
        guard showCaption, let body = entry?.body, !body.isEmpty else { return nil }
        return body
    }

    // MARK: - State

    @State private var aspect: AspectRatio = .square
    @State private var showMetrics: Bool = true
    @State private var showDate: Bool = true
    @State private var showCaption: Bool = true
    @State private var photoSource: PhotoSource = .profile
    @State private var customPhotoItem: PhotosPickerItem?
    @State private var customPhotoData: Data?
    @State private var renderedImage: UIImage?
    @State private var showingShareSheet = false
    @State private var saveToastMessage: String?

    enum AspectRatio: String, CaseIterable {
        case square = "1:1", portrait = "4:5", story = "9:16"
        var size: CGSize {
            switch self {
            case .square:   return CGSize(width: 1080, height: 1080)
            case .portrait: return CGSize(width: 1080, height: 1350)
            case .story:    return CGSize(width: 1080, height: 1920)
            }
        }
    }

    enum PhotoSource { case entry, profile, custom }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    previewCard
                    aspectPicker
                    controls
                    actionButtons
                }
                .padding(20)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .presentationDragIndicator(.visible)
            .navigationTitle(String(localized: "share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { photoSource = entryPhotoData != nil ? .entry : .profile }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = renderedImage { ShareSheet(items: [image]) }
            }
        }
    }

    // MARK: - Preview card

    @MainActor private var previewCard: some View {
        cardContent
            .aspectRatio(aspect.size.width / aspect.size.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.xl).stroke(AppColors.rule, lineWidth: 1))
    }

    @MainActor private var cardContent: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                // 사진 full-bleed
                photoLayer(width: w, height: h)
                // 하단 그라데이션
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center, endPoint: .bottom
                )
                // 텍스트 overlay
                VStack(alignment: .leading, spacing: 4) {
                    if showMetrics {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(rateString)
                                .font(.system(size: w * 0.14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                            Text("s/d")
                                .font(.system(size: w * 0.045, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    Text((effectiveWatch?.brand ?? "").uppercased())
                        .font(.system(size: w * 0.035, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(effectiveWatch?.model ?? "")
                        .font(.system(size: w * 0.028))
                        .foregroundStyle(.white.opacity(0.65))
                    if let caption = captionText {
                        Text(caption)
                            .font(.system(size: w * 0.025))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                    // watermark
                    HStack {
                        Text("ticklab")
                            .font(.system(size: w * 0.02, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        if showDate {
                            Text(dateString)
                                .font(.system(size: w * 0.02, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(w * 0.07)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: w, height: h)
        }
    }

    @ViewBuilder
    private func photoLayer(width: CGFloat, height: CGFloat) -> some View {
        let img: UIImage? = {
            switch photoSource {
            case .entry:   return entryPhotoData.flatMap { UIImage(data: $0) }
            case .custom:  return customPhotoData.flatMap { UIImage(data: $0) }
            case .profile:
                guard let w = effectiveWatch else { return nil }
                return PhotoCache.image(for: w.id, data: w.photoData)
            }
        }()
        if let img {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: width, height: height).clipped()
        } else {
            AppColors.primaryDeep
                .overlay {
                    if let w = effectiveWatch { WatchSilhouette(watch: w, size: width * 0.55) }
                }
        }
    }

    // MARK: - Aspect picker

    private var aspectPicker: some View {
        Picker(String(localized: "share.aspect.a11y"), selection: $aspect) {
            ForEach(AspectRatio.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .tint(AppColors.accent)
        .accessibilityLabel(String(localized: "share.aspect.a11y"))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 4) {
            Toggle(String(localized: "share.show_metrics"), isOn: $showMetrics)
            Toggle(String(localized: "share.show_date"), isOn: $showDate)
            Toggle(String(localized: "share.show_caption"), isOn: $showCaption)
            // 사진 소스 선택
            HStack {
                Text(String(localized: "share.photo_source")).font(AppTypography.body)
                Spacer()
                HStack(spacing: 0) {
                    if entryPhotoData != nil {
                        photoSourceBtn(String(localized: "share.photo_entry"), .entry)
                    }
                    photoSourceBtn(String(localized: "share.photo_profile"), .profile)
                    photoSourceBtn(String(localized: "share.photo_custom"), .custom)
                }
                .background(AppColors.paper2)
                .clipShape(Capsule())
            }
            if photoSource == .custom {
                PhotosPicker(selection: $customPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label(
                        customPhotoData == nil
                            ? String(localized: "share.photo_pick")
                            : String(localized: "share.photo_change"),
                        systemImage: "photo.on.rectangle"
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                }
                .onChange(of: customPhotoItem) { _, item in
                    Task { customPhotoData = try? await item?.loadTransferable(type: Data.self) }
                }
            }
        }
        .tint(AppColors.accent)
    }

    private func photoSourceBtn(_ label: String, _ source: PhotoSource) -> some View {
        let selected = photoSource == source
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { photoSource = source }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .white : AppColors.ink2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? AppColors.ink0 : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action buttons

    @MainActor private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                render { image in renderedImage = image; showingShareSheet = true }
            } label: {
                Label(String(localized: "share.export"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity).padding(14)
                    .background(AppColors.primaryDeep)
                    .foregroundStyle(AppColors.paper0)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .buttonStyle(.plain)

            Button {
                render { image in
                    let saver = PhotoLibrarySaver { success in
                        Task { @MainActor in
                            if success {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                saveToastMessage = String(localized: "share.save.success")
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                saveToastMessage = String(localized: "share.save.failed")
                            }
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            saveToastMessage = nil
                        }
                    }
                    UIImageWriteToSavedPhotosAlbum(image, saver, #selector(PhotoLibrarySaver.image(_:didFinishSavingWithError:contextInfo:)), nil)
                    // Saver 인스턴스 유지 (selector 콜백 대기)
                    PhotoLibrarySaver.activeSavers.append(saver)
                }
            } label: {
                Label(String(localized: "share.save_to_photos"), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity).padding(14)
                    .background(AppColors.paper1)
                    .foregroundStyle(AppColors.ink0)
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .top) {
            if let msg = saveToastMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.85))
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, -50)
            }
        }
        .animation(.easeOut(duration: 0.2), value: saveToastMessage)
    }

    @MainActor
    private func render(completion: (UIImage) -> Void) {
        let renderer = ImageRenderer(
            content: cardContent.frame(width: aspect.size.width, height: aspect.size.height)
        )
        renderer.scale = 2
        if let image = renderer.uiImage { completion(image) }
    }
}

// MARK: - ShareSheet

/// 사진 라이브러리 저장 콜백 핸들러 (NSObject + @objc selector 필요).
private final class PhotoLibrarySaver: NSObject {
    static var activeSavers: [PhotoLibrarySaver] = []
    let completion: (Bool) -> Void
    init(completion: @escaping (Bool) -> Void) { self.completion = completion }

    @objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        completion(error == nil)
        // active 리스트에서 자기 자신 제거 → ARC 해제
        Self.activeSavers.removeAll { $0 === self }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
