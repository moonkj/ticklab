import SwiftUI

/// 스트림A: 측정 실패 복구 체크리스트.
/// 마지막 진단(마이크 dB·SNR·onset)을 기반으로 무엇이 정상이고 무엇을 고쳐야 하는지
/// ✓/✗ 행으로 보여준다. 블루투스/유선 마이크 감지 시 "내장 마이크로 전환" 안내를 우선 표시.
struct FailureChecklistCard: View {
    /// 한 줄 점검 항목. ok=true → ✓(정상), false → ✗ + 권장 액션.
    struct Item: Identifiable {
        let id = UUID()
        let ok: Bool
        /// 항목 라벨 (예: "마이크", "신호 세기").
        let label: String
        /// ✗ 일 때 사용자에게 권장하는 액션. ok 면 nil.
        let action: String?
    }

    let items: [Item]
    /// 블루투스/유선 마이크 사용 중일 때 표시할 안내(내장 마이크 전환). nil 이면 미표시.
    let externalMicNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "meas.failhelp.title").uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            if let externalMicNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "headphones")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.warning)
                        .accessibilityHidden(true)
                    Text(externalMicNotice)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppColors.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            ForEach(items) { item in
                checklistRow(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func checklistRow(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(item.ok ? AppColors.success : AppColors.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.ink0)
                if let action = item.action {
                    Text(action)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppColors.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 접근성: ✓/✗ 아이콘은 라벨 텍스트로 상태 표현. VoiceOver 가 "정상/확인 필요" 로 읽도록 묶음.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(item))
    }

    private func accessibilityLabel(_ item: Item) -> String {
        let status = item.ok
            ? String(localized: "meas.failhelp.a11y.ok")
            : String(localized: "meas.failhelp.a11y.fix")
        if let action = item.action {
            return "\(item.label), \(status). \(action)"
        }
        return "\(item.label), \(status)"
    }
}

#Preview {
    VStack(spacing: 16) {
        FailureChecklistCard(
            items: [
                .init(ok: true, label: "Microphone", action: nil),
                .init(ok: false, label: "Signal strength", action: "Press the iPhone mic firmly against the caseback."),
                .init(ok: true, label: "Quiet surroundings", action: nil)
            ],
            externalMicNotice: nil
        )
        FailureChecklistCard(
            items: [.init(ok: false, label: "Microphone", action: "No audio detected.")],
            externalMicNotice: "AirPods detected — switch to the built-in iPhone microphone."
        )
    }
    .padding()
    .background(AppColors.paper0)
}
