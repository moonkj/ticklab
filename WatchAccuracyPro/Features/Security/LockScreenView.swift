import SwiftUI

/// Face ID / Touch ID + 선택적 PIN 잠금 화면 (디자인 SSOT screens-detail.jsx LockScreenView).
/// 앱 잠금 활성 + 자동 lock 후 진입 시 표시.
/// - PIN 사용 가능 → PINEntryView 표시
/// - PIN 미설정 또는 5회 실패 lockout → 기존 Face ID 흐름
struct LockScreenView: View {
    let onUnlock: () -> Void
    @ObservedObject private var appLock = AppLockService.shared
    @ObservedObject private var pinService = PINService.shared

    var body: some View {
        Group {
            if appLock.canUsePIN {
                PINEntryView(
                    onUnlock: onUnlock,
                    onUseFaceID: { triggerFaceID() }
                )
            } else {
                faceIDScreen
            }
        }
    }

    // MARK: - Face ID screen

    private var faceIDScreen: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                logoMark
                    .frame(width: 120, height: 120)
                Text(String(localized: "lockscreen.app_name"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                if pinService.isPINLockedOut {
                    Text(String(localized: "pin.entry.locked_out"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Spacer()
                Button {
                    triggerFaceID()
                } label: {
                    VStack(spacing: 16) {
                        Image(systemName: "faceid")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white)
                        Text(String(localized: "lockscreen.faceid.unlock"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 16)
                    .frame(minWidth: 200, minHeight: 56)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        // Round 53: app 전역 .light 가 lock 화면 dark navy 위 텍스트 색 다크 만들지 않도록 .dark override.
        .preferredColorScheme(.dark)
        .onAppear {
            triggerFaceID()
        }
    }

    private func triggerFaceID() {
        Task {
            if await appLock.unlock() {
                onUnlock()
            }
        }
    }

    /// 12 dot ring + TL logo (Welcome 화면과 동일).
    private var logoMark: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) * 30 - 90
                let radians = angle * .pi / 180
                let r: Double = 48
                Circle()
                    .fill(i == 0 ? AppColors.accent : Color.white.opacity(0.7))
                    .frame(
                        width: i == 0 ? 6 : 4,
                        height: i == 0 ? 6 : 4
                    )
                    .offset(x: r * cos(radians), y: r * sin(radians))
            }
            Text("TL")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1.5)
                .foregroundStyle(AppColors.accent)
                .offset(y: 6)
        }
    }
}
