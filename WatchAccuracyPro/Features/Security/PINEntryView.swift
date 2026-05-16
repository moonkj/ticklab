import SwiftUI

/// 잠금 해제용 PIN 입력 화면.
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
    @FocusState private var focused: Bool

    private var remaining: Int {
        max(0, PINService.maxFailureAttempts - pinService.failureCount)
    }

    var body: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            VStack(spacing: 28) {
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
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .background(
                        Capsule().fill(Color.white.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)

                // 시스템 키보드 (숨김).
                TextField("", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.01)
                    .frame(height: 1)
                    .disabled(pinService.isPINLockedOut)
                    .accessibilityLabel(String(localized: "pin.entry.title"))
                    .accessibilityHint(String(localized: "pin.entry.a11y.hint"))
                    .onChange(of: pin) { _, newValue in
                        handlePINChange(newValue)
                    }
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !pinService.isPINLockedOut {
                focused = true
            }
        }
        .onTapGesture {
            if !pinService.isPINLockedOut {
                focused = true
            }
        }
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

    private func handlePINChange(_ newValue: String) {
        if pinService.isPINLockedOut {
            pin = ""
            return
        }
        let filtered = newValue.filter { $0.isNumber }
        if filtered != newValue {
            pin = filtered
            return
        }
        if filtered.count > PINService.pinLength {
            pin = String(filtered.prefix(PINService.pinLength))
            return
        }
        lastAttemptFailed = false
        if filtered.count == PINService.pinLength {
            let success = appLock.unlockWithPIN(filtered)
            if success {
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
}

#Preview {
    PINEntryView(onUnlock: {}, onUseFaceID: {})
}
