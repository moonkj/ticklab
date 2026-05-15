import SwiftUI

/// Screen 25 — DialFortune. 오늘의 다이얼 운세. 다크 네이비 풀스크린.
struct DialFortuneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let today = Date()

    /// 날짜 기반 deterministic seed.
    private var seed: Int {
        let cal = Calendar.current
        let day = cal.ordinality(of: .day, in: .year, for: today) ?? 1
        return day
    }

    private struct Fortune {
        let day: String
        let luckyDial: String
        let luckyDialColor: Color
        let luckyComplication: String
        let unluckyDial: String
        let luckyNumber: Int
        let horoscope: String
        let love: Int
        let work: Int
        let money: Int
        let health: Int
        let rituals: [String]
    }

    // Round 105 (Hard Rule 3 + 다나카 Critical): 모든 인라인 문자열 Localizable 이동.
    private var fortune: Fortune {
        let dials: [(name: String, color: Color)] = [
            (String(localized: "fortune.dial.blue"),    Color(red: 0.122, green: 0.220, blue: 0.392)),
            (String(localized: "fortune.dial.black"),   Color(red: 0.10, green: 0.10, blue: 0.12)),
            (String(localized: "fortune.dial.green"),   Color(red: 0.10, green: 0.35, blue: 0.18)),
            (String(localized: "fortune.dial.silver"),  Color(red: 0.85, green: 0.85, blue: 0.87)),
            (String(localized: "fortune.dial.champagne"), Color(red: 0.85, green: 0.72, blue: 0.48)),
            (String(localized: "fortune.dial.panda"),   Color(red: 0.92, green: 0.92, blue: 0.92)),
        ]
        // Round 133 BUG FIX (사용자 보고: "fortune.horoscope.3" 키 그대로 노출):
        // String(localized: ...) 는 LocalizationValue 가 interpolation 포함 시 key lookup 실패.
        // NSLocalizedString 사용해 raw key 문자열로 lookup 강제.
        let complications = (1...5).map { NSLocalizedString("fortune.complication.\($0)", comment: "") }
        let unluckies = (1...4).map { NSLocalizedString("fortune.unlucky.\($0)", comment: "") }
        let rituals = (1...6).map { NSLocalizedString("fortune.ritual.\($0)", comment: "") }
        let horoscopes = (1...5).map { NSLocalizedString("fortune.horoscope.\($0)", comment: "") }

        let dial = dials[seed % dials.count]
        let love = 3 + (seed % 3)
        let work = 3 + ((seed + 1) % 3)
        let money = 2 + ((seed + 2) % 4)
        let health = 3 + ((seed + 3) % 3)
        return Fortune(
            day: today.formatted(.dateTime.weekday(.wide).month().day()),
            luckyDial: dial.name,
            luckyDialColor: dial.color,
            luckyComplication: complications[seed % complications.count],
            unluckyDial: unluckies[(seed + 1) % unluckies.count],
            luckyNumber: 1 + (seed % 12),
            horoscope: horoscopes[seed % horoscopes.count],
            love: love, work: work, money: money, health: health,
            rituals: Array([rituals[seed % rituals.count],
                            rituals[(seed + 2) % rituals.count],
                            rituals[(seed + 4) % rituals.count]])
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                titleSection
                heroDial
                verdictSection
                pillsRow
                metricQuad
                ritualSection
                shareCta
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.102, green: 0.106, blue: 0.180),
                    Color(red: 0.165, green: 0.133, blue: 0.20),
                    Color(red: 0.239, green: 0.247, blue: 0.431)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        // Round 139 (Jay High): navigationTitle 누락 — 빈 nav bar.
        .navigationTitle(String(localized: "fortune.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text(String(localized: "fortune.title.eyebrow").uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(AppColors.accent)
            Text(fortune.day)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.top, 14)
    }

    private var heroDial: some View {
        ZStack {
            // Cosmic ring
            Circle()
                .stroke(AngularGradient(colors: [
                    AppColors.accent, .clear, AppColors.primary500, .clear, AppColors.accent
                ], center: .center), lineWidth: 2)
                .opacity(0.5)
                .frame(width: 260, height: 260)
                .rotationEffect(.degrees(rotationAngle))

            // Stars
            ForEach(0..<12, id: \.self) { i in
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 3, height: 3)
                    .opacity(i.isMultiple(of: 2) ? 0.9 : 0.4)
                    .offset(y: -130)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // Dial
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [fortune.luckyDialColor.opacity(0.9),
                                 fortune.luckyDialColor,
                                 fortune.luckyDialColor.opacity(0.4)],
                        center: UnitPoint(x: 0.35, y: 0.25),
                        startRadius: 5, endRadius: 200))
                    .frame(width: 220, height: 220)
                    .shadow(color: fortune.luckyDialColor.opacity(0.6),
                            radius: 30, x: 0, y: 20)

                // Indices
                ForEach(0..<12, id: \.self) { i in
                    let major = [0, 3, 6, 9].contains(i)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppColors.accent)
                        .frame(width: major ? 4 : 2, height: major ? 14 : 8)
                        .offset(y: -86)
                        .rotationEffect(.degrees(Double(i) * 30))
                }

                VStack(spacing: 4) {
                    Text(String(localized: "fortune.lucky_number"))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(AppColors.accent)
                    Text("\(fortune.luckyNumber)")
                        .font(.system(size: 60, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 4)
                }
            }
        }
        .frame(height: 280)
        .onAppear {
            // Round 115 (A11y): reduce motion 사용자에게 무한 회전 미실행.
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
        // Round 147 (Sora 4 #4): onDisappear 정지 누락 → SwiftUI runtime animation driver leak.
        .onDisappear {
            withAnimation(nil) { rotationAngle = 0 }
        }
    }

    @State private var rotationAngle: Double = 0

    private var verdictSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Text(String(localized: "fortune.today_prefix"))
                Text(fortune.luckyDial)
                    .foregroundStyle(AppColors.accent)
                Text(String(localized: "fortune.today_suffix"))
            }
            .font(.system(size: 24, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)

            Text(fortune.horoscope)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    private var pillsRow: some View {
        HStack(spacing: 8) {
            fortunePill(label: String(localized: "fortune.pill.lucky"), value: fortune.luckyComplication, danger: false)
            fortunePill(label: String(localized: "fortune.pill.unlucky"), value: fortune.unluckyDial, danger: true)
        }
    }

    private func fortunePill(label: String, value: String, danger: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(danger ? Color.red.opacity(0.12) : AppColors.accent.opacity(0.18))
        .overlay(Capsule().stroke(danger ? Color.red.opacity(0.3)
                                  : AppColors.accent.opacity(0.5), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var metricQuad: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                metric(String(localized: "fortune.metric.love"), score: fortune.love)
                metric(String(localized: "fortune.metric.work"), score: fortune.work)
            }
            HStack(spacing: 16) {
                metric(String(localized: "fortune.metric.money"), score: fortune.money)
                metric(String(localized: "fortune.metric.health"), score: fortune.health)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ name: String, score: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= score ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(i <= score ? AppColors.accent : Color.white.opacity(0.15))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ritualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "fortune.rituals.title").uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.5)
                .foregroundStyle(AppColors.accent)
            VStack(spacing: 0) {
                ForEach(Array(fortune.rituals.enumerated()), id: \.offset) { idx, r in
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 22, height: 22)
                            .background(AppColors.accent.opacity(0.18))
                            .clipShape(Circle())
                        Text(r)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    if idx < fortune.rituals.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                }
            }
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Round 169: 실제 ShareLink 로 운세 텍스트 공유 구현.
    private var shareCta: some View {
        // Round 105 (Hard Rule 3): ShareLink 본문 한국어 inline → localize.
        let shareText = String(format: String(localized: "fortune.share.text"),
                               fortune.day, fortune.luckyDial, fortune.luckyNumber,
                               fortune.horoscope, fortune.luckyComplication, fortune.unluckyDial)
        return ShareLink(item: shareText) {
            Text(String(localized: "fortune.share.cta"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.primaryDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppColors.accent.opacity(0.4), radius: 8, y: 4)
        }
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack { DialFortuneView() }
}
