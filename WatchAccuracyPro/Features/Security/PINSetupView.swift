import SwiftUI

/// 6자리 PIN 설정/변경 화면.
/// 두 단계: enter → confirm. 일치 시 PINService.setPIN 후 dismiss.
struct PINSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences
    @ObservedObject private var pinService = PINService.shared

    @State private var step: Step = .enter
    @State private var firstPIN: String = ""
    @State private var confirmPIN: String = ""
    @State private var mismatch: Bool = false
    @State private var showSuccess: Bool = false
    @FocusState private var focused: Bool

    private enum Step {
        case enter
        case confirm
    }

    private var currentPINBinding: Binding<String> {
        switch step {
        case .enter:   return $firstPIN
        case .confirm: return $confirmPIN
        }
    }

    private var currentPIN: String {
        step == .enter ? firstPIN : confirmPIN
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 8)

            Text(String(localized: "pin.setup.title"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.ink0)

            Text(stepPrompt)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)

            pinDots(filled: currentPIN.count)

            if mismatch {
                Text(String(localized: "pin.setup.mismatch"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.danger)
            }

            if showSuccess {
                Text(String(localized: "pin.setup.success"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.success)
            }

            // 보이지 않는 numeric 입력 (시스템 키보드).
            TextField("", text: currentPINBinding)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.01)
                .frame(height: 1)
                .onChange(of: currentPIN) { _, newValue in
                    handlePINChange(newValue)
                }

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.paper0.ignoresSafeArea())
        // Round 139 (Jay Critical): navigationTitle 누락 — PIN 입력 중 어느 화면인지 모름.
        .navigationTitle(String(localized: "pin.setup.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onTapGesture { focused = true }
        // Round 140 (Min H7): setup 미완료 상태로 dismiss 시 pinEnabled false 로 복귀 — Face ID-only 잠금 방지.
        .onDisappear {
            if !PINService.shared.hasPIN {
                preferences.pinEnabled = false
            }
        }
    }

    private var stepPrompt: String {
        switch step {
        case .enter:   return String(localized: "pin.setup.enter")
        case .confirm: return String(localized: "pin.setup.confirm")
        }
    }

    private func pinDots(filled: Int) -> some View {
        HStack(spacing: 16) {
            ForEach(0..<PINService.pinLength, id: \.self) { i in
                Circle()
                    .fill(i < filled ? AppColors.accent : AppColors.rule)
                    .frame(width: 14, height: 14)
            }
        }
    }

    private func handlePINChange(_ newValue: String) {
        // 숫자가 아닌 문자 차단.
        let filtered = newValue.filter { $0.isNumber }
        if filtered != newValue {
            currentPINBinding.wrappedValue = filtered
            return
        }
        // 길이 초과 방지.
        if filtered.count > PINService.pinLength {
            currentPINBinding.wrappedValue = String(filtered.prefix(PINService.pinLength))
            return
        }
        mismatch = false
        if filtered.count == PINService.pinLength {
            switch step {
            case .enter:
                step = .confirm
                focused = true
            case .confirm:
                attemptCommit()
            }
        }
    }

    private func attemptCommit() {
        guard firstPIN == confirmPIN else {
            mismatch = true
            // 다시 처음부터 입력.
            confirmPIN = ""
            firstPIN = ""
            step = .enter
            focused = true
            return
        }
        do {
            try pinService.setPIN(firstPIN)
            showSuccess = true
            // 가벼운 딜레이 후 dismiss — 사용자가 성공 메시지 확인.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } catch {
            mismatch = true
            confirmPIN = ""
            firstPIN = ""
            step = .enter
        }
    }
}

#Preview {
    NavigationStack { PINSetupView() }
}
