import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// 시계 스펙 카드 작성 화면.
/// 사용자가 등록한 시계 기반 — 사진 첨부 + 무브먼트/사이즈 입력 + 5초 사운드 녹음.
struct SpecCardComposerView: View {
    let watch: Watch
    var existing: SpecCard? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var movement: String = ""
    @State private var caseSizeText: String = ""
    @State private var powerReserveText: String = ""
    @State private var note: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showingCamera: Bool = false
    @StateObject private var recorder = SpecCardRecorder()
    /// Round 147: 무브먼트 picker mode.
    @State private var useCustomMovement: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoSection
                    titleSection
                    specRows
                    soundRecorderSection
                    noteSection
                }
                .padding(16)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "speccard.nav.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) { save() }.fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private var photoSection: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [AppColors.accent50, AppColors.paper2],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Round 146: 사용자가 등록한 watch.photoData 자동 연동.
                if let data = photoData ?? watch.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    WatchSilhouette(watch: watch, size: 140)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // Round 154: 보관함 + 카메라 두 버튼.
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                        Text(String(localized: photoData == nil ? "speccard.photo.add" : "speccard.photo.change"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.accent)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.accent50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button {
                    showingCamera = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                        Text(String(localized: "speccard.camera"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.accentDark)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .onChange(of: photoItem) { _, new in
                Task {
                    if let new, let raw = try? await new.loadTransferable(type: Data.self) {
                        // Round 84 (Security): EXIF strip 후 저장.
                        photoData = EXIFStripper.strippedJPEG(from: raw)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraImagePicker(imageData: $photoData)
                .ignoresSafeArea()
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "speccard.title.label"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.ink2)
            TextField("\(watch.brand) \(watch.model)", text: $title)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var specRows: some View {
        VStack(spacing: 8) {
            // Round 147: 무브먼트 — Picker (목록) + 직접 입력 toggle.
            movementPickerRow
            specField(label: String(localized: "speccard.field.case_size"),
                      value: $caseSizeText,
                      placeholder: String(localized: "speccard.field.placeholder.case"),
                      keyboard: .decimalPad)
            specField(label: String(localized: "speccard.field.power_reserve"),
                      value: $powerReserveText,
                      placeholder: String(localized: "speccard.field.placeholder.power"),
                      keyboard: .decimalPad)
        }
    }

    /// Round 147: 무브먼트 picker — MovementDatabase 목록 + "직접 입력".
    private var movementPickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "speccard.movement"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                Toggle(String(localized: "speccard.movement.custom_toggle"), isOn: $useCustomMovement)
                    .toggleStyle(.button)
                    .font(.system(size: 11, weight: .medium))
                    .controlSize(.small)
            }
            if useCustomMovement {
                TextField(String(localized: "speccard.movement.custom_placeholder"), text: $movement)
                    .textFieldStyle(.roundedBorder)
            } else {
                Menu {
                    Button(String(localized: "speccard.movement.none")) { movement = "" }
                    Divider()
                    ForEach(MovementDatabase.shared.movements, id: \.id) { m in
                        Button("\(m.id) · \(m.bph) BPH") {
                            movement = m.id
                        }
                    }
                } label: {
                    HStack {
                        Text(movement.isEmpty ? String(localized: "speccard.movement.pick") : movement)
                            .foregroundStyle(movement.isEmpty ? AppColors.ink3 : AppColors.ink0)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.ink2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.paper1)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func specField(label: String, value: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: value)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var soundRecorderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "speccard.sound.section"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.ink2)
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await recorder.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(recorder.isRecording ? AppColors.danger : AppColors.accent)
                        Text(recorder.isRecording ?
                                String(format: NSLocalizedString("speccard.record.recording", comment: ""), recorder.elapsedSec) :
                                (recorder.hasRecording ?
                                    String(localized: "speccard.record.again") :
                                    String(localized: "speccard.record.start")))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.ink0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.paper1)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                if recorder.hasRecording {
                    Button {
                        Task { await recorder.play() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            if let err = recorder.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.danger)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "speccard.note"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.ink2)
            TextField(String(localized: "speccard.note.placeholder"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func loadExisting() {
        guard let existing else {
            title = "\(watch.brand) \(watch.model)"
            return
        }
        title = existing.title
        movement = existing.movement
        caseSizeText = existing.caseSize.map { String(format: "%.1f", $0) } ?? ""
        powerReserveText = existing.powerReserveHours.map { String(format: "%.0f", $0) } ?? ""
        note = existing.note
        // photo / audio load — 파일 path 읽음.
        if let pp = existing.photoPath, let data = try? Data(contentsOf: URL(fileURLWithPath: pp)) {
            photoData = data
        }
        if let ap = existing.audioPath {
            recorder.loadExisting(path: ap)
        }
    }

    private func save() {
        // 사진 파일 저장 (EXIF stripped).
        var photoPath: String? = nil
        if let data = photoData {
            photoPath = EXIFStripper.savePhoto(data)
        }
        // 사운드 파일 save (recorder 가 이미 disk 에 임시 저장)
        let audioPath = recorder.persistedPath

        let card = existing ?? SpecCard(watch: watch)
        card.title = title.isEmpty ? "\(watch.brand) \(watch.model)" : title
        card.movement = movement
        card.caseSize = Double(caseSizeText)
        card.powerReserveHours = Double(powerReserveText)
        if let photoPath { card.photoPath = photoPath }
        if let audioPath { card.audioPath = audioPath }
        card.note = note
        if existing == nil { modelContext.insert(card) }
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// 5초 무브먼트 사운드 녹음/재생.
/// Round 155: AVAudioRecorder.stop() 후 m4a MOOV atom 작성이 비동기로 끝남 →
/// 즉시 파일을 옮기면 truncated container 가 되어 재생 실패. delegate 콜백 대기로 해결.
@MainActor
final class SpecCardRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var elapsedSec = 0
    @Published var lastError: String?
    private(set) var persistedPath: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerDelegate?
    private var recorderDelegate: RecorderDelegate?
    private var timer: Timer?
    private let maxSeconds = 5

    /// 재생 종료 callback.
    private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }
    }

    /// 녹음 종료 callback — m4a 파일 finalization 완료 시 호출됨.
    private final class RecorderDelegate: NSObject, AVAudioRecorderDelegate {
        let onFinish: (Bool, URL) -> Void
        init(onFinish: @escaping (Bool, URL) -> Void) { self.onFinish = onFinish }
        func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
            onFinish(flag, recorder.url)
        }
        func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
            onFinish(false, recorder.url)
        }
    }

    func toggle() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    private func start() async {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("speccard_\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            let delegate = RecorderDelegate { [weak self] success, url in
                Task { @MainActor in
                    self?.finalizeRecording(success: success, url: url)
                }
            }
            recorderDelegate = delegate
            r.delegate = delegate
            r.isMeteringEnabled = false
            guard r.prepareToRecord() else {
                lastError = String(localized: "speccard.record.error.prep")
                return
            }
            recorder = r
            r.record(forDuration: TimeInterval(maxSeconds))
            isRecording = true
            elapsedSec = 0
            persistedPath = nil
            hasRecording = false
            lastError = nil
            startTimer()
        } catch {
            lastError = String(format: NSLocalizedString("speccard.record.error.start", comment: ""), error.localizedDescription)
        }
    }

    private func stop() {
        // 수동 stop — record(forDuration:) 가 끝나기 전에 사용자가 누른 경우.
        // delegate.audioRecorderDidFinishRecording 이 비동기로 호출되어 finalize 됨.
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    /// AVAudioRecorder delegate 콜백 — m4a 파일이 완전히 flush 된 시점.
    private func finalizeRecording(success: Bool, url: URL) {
        timer?.invalidate()
        timer = nil
        isRecording = false
        defer {
            // 재생 라우팅 안정화를 위해 record 세션 deactivate.
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            recorder = nil
        }
        guard success else {
            lastError = String(localized: "speccard.record.error.failed")
            return
        }
        // 영구 저장소로 이동.
        do {
            let fm = FileManager.default
            let supportDir = try fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let dir = supportDir.appendingPathComponent("speccard-audio", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: url, to: dest)
            // 파일 사이즈 sanity check.
            let size = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
            guard size > 1024 else {
                lastError = String(localized: "speccard.record.error.short")
                try? fm.removeItem(at: dest)
                return
            }
            persistedPath = dest.path
            hasRecording = true
        } catch {
            lastError = String(format: NSLocalizedString("speccard.record.error.save", comment: ""), error.localizedDescription)
        }
    }

    func play() async {
        guard let path = persistedPath else {
            lastError = String(localized: "speccard.play.error.no_file")
            return
        }
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            lastError = String(localized: "speccard.play.error.missing")
            return
        }
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size > 1024 else {
            lastError = String(localized: "speccard.play.error.empty")
            return
        }
        if let p = player, p.isPlaying {
            p.stop()
            player = nil
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            let p = try AVAudioPlayer(contentsOf: url)
            playerDelegate = PlayerDelegate { [weak self] in
                Task { @MainActor in self?.player = nil }
            }
            p.delegate = playerDelegate
            p.volume = 1.0
            guard p.prepareToPlay() else {
                lastError = String(localized: "speccard.play.error.prep")
                return
            }
            player = p
            if !p.play() {
                lastError = String(localized: "speccard.play.error.start")
            }
        } catch {
            lastError = String(format: NSLocalizedString("speccard.play.error.failed", comment: ""), error.localizedDescription)
        }
    }

    func loadExisting(path: String) {
        if FileManager.default.fileExists(atPath: path) {
            persistedPath = path
            hasRecording = true
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                self.elapsedSec += 1
                if self.elapsedSec >= self.maxSeconds {
                    // record(forDuration:) 가 알아서 stop 후 delegate 발화시킴.
                    // timer 만 정리.
                    t.invalidate()
                    self.timer = nil
                }
            }
        }
    }
}
