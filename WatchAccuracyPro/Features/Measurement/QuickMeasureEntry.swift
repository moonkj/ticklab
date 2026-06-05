import SwiftUI

// MARK: - Quick Measure entry (등록 없이 빠른 측정)
//
// 입문자 첫 경험 마찰↓ — 시계를 등록하지 않고 마이크 정확도를 바로 맛본다.
// 결과는 표시되지만 SwiftData 에 저장되지 않는다(transient). 저장하려면 시계 등록 유도.
//
// 이 파일은 Measurement 도메인 자립 진입점 — 다른 도메인(Collection 빈 상태 등)이
// 한 줄로 `.quickMeasureSheet(...)` 를 붙여 진입할 수 있게 한다. AddWatchView 진입은
// 호출 측에서 `onRegisterWatch` 콜백으로 주입(도메인 경계 보존).

/// 빠른 측정을 sheet 로 띄우는 화면 — NavigationStack 래핑(측정 화면 push 전제 충족)·닫기 버튼 포함.
/// `onRegisterWatch` 가 있으면 결과 화면의 "시계 등록" CTA 로 전달되고, 누르면 sheet 를 닫은 뒤 콜백 실행.
struct QuickMeasureSheet: View {
    let preferences: UserPreferences
    /// "시계 등록" CTA — 호출 측에서 AddWatchView 제시 등으로 연결. nil 이면 안내 텍스트만.
    var onRegisterWatch: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MeasurementView(
                quickMeasure: preferences,
                onRegisterWatch: onRegisterWatch.map { register in
                    {
                        // 등록 진입 전 빠른 측정 sheet 를 닫아 화면 충돌 방지.
                        dismiss()
                        register()
                    }
                }
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
        }
    }
}

extension View {
    /// 빠른 측정 sheet 진입 modifier — 호출 측은 Bool 바인딩만 토글하면 된다.
    /// 예: `.quickMeasureSheet(isPresented: $showQuick, preferences: preferences) { showingAdd = true }`
    func quickMeasureSheet(
        isPresented: Binding<Bool>,
        preferences: UserPreferences,
        onRegisterWatch: (() -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            QuickMeasureSheet(preferences: preferences, onRegisterWatch: onRegisterWatch)
        }
    }
}

#Preview {
    QuickMeasureSheet(preferences: UserPreferences())
        .environment(UserPreferences())
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
