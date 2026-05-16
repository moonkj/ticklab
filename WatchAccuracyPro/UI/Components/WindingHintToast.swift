import SwiftUI

/// 측정 시작 화면 진입 시 quartz 가 아닌 시계 (auto/manual) 에 1일/1회 플로팅 카드.
/// 사용자 보고: 풀와인딩 안 한 시계 측정 시 -45 s/d 같은 큰 음수 → "측정 오류" 오해 → 재측정 반복.
/// 인라인 카드는 인지율 낮음 — modal 형식 floating card 로 사용자 주의 환기.
struct WindingHintToast: View {
    /// confirmed=true 면 24h timestamp 저장. dim tap 등 무심 dismiss 시 false 로 호출 → 다음 진입 다시 표시.
    let onDismiss: (Bool) -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // 반투명 dim — modal 임을 시각적으로 강조 (tap = dismiss but not "confirmed").
            Color.black.opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss(confirmed: false) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(String(localized: "common.close"))

            VStack(spacing: 18) {
                // Header — 큰 아이콘 + 제목
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "key.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppColors.accentDark)
                        .rotationEffect(.degrees(-45))
                }
                .padding(.top, 4)

                Text(String(localized: "measurement.winding_hint.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .multilineTextAlignment(.center)

                Text(String(localized: "measurement.winding_hint.body"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                // CTA — "확인했어요": 24h timestamp 저장.
                Button { dismiss(confirmed: true) } label: {
                    Text(String(localized: "measurement.winding_hint.cta"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppColors.primaryDeep)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "measurement.winding_hint.cta"))
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(AppColors.paper0)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                appeared = true
            }
        }
    }

    private func dismiss(confirmed: Bool) {
        withAnimation(.easeOut(duration: 0.2)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss(confirmed)
        }
    }
}
