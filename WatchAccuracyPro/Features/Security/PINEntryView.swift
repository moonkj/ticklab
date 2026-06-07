import SwiftUI

/// 잠금 해제용 PIN 입력 화면.
/// - 화면 내장 커스텀 키패드(시스템 키보드 X) — 잠금화면에 키보드가 갑자기 뜨는 어색함 제거.
/// - 6자리 입력 시 자동 검증.
/// - 5회 실패 시 경고 배너 + Face ID 로 fallback 강제.
/// - 사용자가 직접 Face ID 선택 가능.
struct PINEntryView: View {
    let onUnlock: () -> Void
    let onUseFaceID: () -> Void

    @ObservedObject private var pinService = PINService.shared
    @ObservedObject private var appLock = AppLockService.shared

    @State private var pin: String = ""
    @State private var lastAttemptFailed: Bool = false

    private var remaining: Int {
        max(0, PINService.maxFailureAttempts - pinService.failureCount)
    }

    var body: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer().frame(height: 16)

                Text(String(localized: "pin.entry.title"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                pinDots(filled: pin.count, failed: lastAttemptFailed)

                if pinService.isPINLockedOut {
                    lockedOutBanner
                } else {
                    Text(String(format: String(localized: "pin.entry.remaining"), remaining))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                Spacer()

                // 화면 내장 키패드 — 탭 시 즉시 입력(시스템 키보드 미사용).
                PINKeypad(onDigit: append, onDelete: deleteLast, disabled: pinService.isPINLockedOut)

                Button {
                    onUseFaceID()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 18, weight: .light))
                        Text(String(localized: "pin.entry.use_face_id"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: pin.count)
        .sensoryFeedback(.error, trigger: lastAttemptFailed) { _, now in now }
    }

    private var lockedOutBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.warning)
            Text(String(localized: "pin.entry.locked_out"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func pinDots(filled: Int, failed: Bool) -> some View {
        HStack(spacing: 16) {
            ForEach(0..<PINService.pinLength, id: \.self) { i in
                Circle()
                    .fill(
                        failed
                            ? AppColors.danger
                            : (i < filled ? AppColors.accent : Color.white.opacity(0.25))
                    )
                    .frame(width: 14, height: 14)
            }
        }
        .animation(.easeOut(duration: 0.18), value: filled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: NSLocalizedString("pin.entry.a11y.progress", comment: ""), filled, PINService.pinLength)))
        .accessibilityValue(failed ? Text(String(localized: "pin.entry.a11y.failed")) : Text(""))
    }

    // MARK: - 입력 처리

    private func append(_ digit: String) {
        guard !pinService.isPINLockedOut, pin.count < PINService.pinLength else { return }
        lastAttemptFailed = false
        pin += digit
        if pin.count == PINService.pinLength { validate() }
    }

    private func deleteLast() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func validate() {
        if appLock.unlockWithPIN(pin) {
            onUnlock()
        } else {
            lastAttemptFailed = true
            // 짧은 딜레이 후 초기화 (사용자가 빨간 점 확인 가능).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                pin = ""
                lastAttemptFailed = false
            }
        }
    }
}

/// 잠금화면용 커스텀 숫자 키패드 — 1~9·0·삭제. 다크 톤(흰 글자 + 반투명 원).
struct PINKeypad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    var disabled: Bool = false

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "\u{232B}"]]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 26) {
                    ForEach(rows[r], id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 70, height: 70)
        } else if key == "\u{232B}" {
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.delete"))
        } else {
            Button { onDigit(key) } label: {
                Text(key)
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(PINKeyButtonStyle())
        }
    }
}

/// 키 눌림 시 살짝 밝아지는 피드백.
private struct PINKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                Circle().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    PINEntryView(onUnlock: {}, onUseFaceID: {})
}
