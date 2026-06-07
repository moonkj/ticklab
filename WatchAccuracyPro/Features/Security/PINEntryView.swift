import LocalAuthentication
import SwiftUI

/// 잠금 해제 화면 — 밸런스 휠을 "잠금의 엔진"으로 한 컨셉.
/// - Face ID 설정 시 진입 즉시 자동 인증 → 성공하면 휠이 빠르게 회전하며 풀림.
/// - Face ID 없음/실패 시 키패드 노출(또는 "PIN 입력" 탭) → 숫자 입력마다 휠이 조금씩 돌고,
///   6자리가 맞으면 빠르게 회전하며 풀림. 틀리면 화면이 흔들리고 휠은 idle 로 복귀.
/// - 시스템 키보드 미사용(화면 내장 커스텀 키패드). reduceMotion 시 모션 생략.
struct PINEntryView: View {
    let onUnlock: () -> Void

    @ObservedObject private var pinService = PINService.shared
    @ObservedObject private var appLock = AppLockService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pin: String = ""
    @State private var lastAttemptFailed = false
    @State private var showKeypad: Bool
    @State private var wheelAngle: Double = 0      // 자리 입력 bump + 해제 고속 회전
    @State private var tremor: Double = -2         // idle 미세 진동
    @State private var unlocking = false
    @State private var shakeAmount: CGFloat = 0
    @State private var didAutoFaceID = false

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
        // 생체 인증이 안 되는 기기/설정이면 키패드를 바로 노출(불필요한 Face ID 프롬프트 회피).
        _showKeypad = State(initialValue: !Self.biometricsReady())
    }

    private var remaining: Int {
        max(0, PINService.maxFailureAttempts - pinService.failureCount)
    }
    private var locked: Bool { pinService.isPINLockedOut || unlocking }
    private var biometricsAvailable: Bool { Self.biometricsReady() }

    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let goldLight = Color(red: 0.91, green: 0.79, blue: 0.48)

    var body: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer().frame(height: 8)

                Text(String(localized: "pin.entry.title"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                wheelStack
                    .frame(width: 132, height: 132)

                pinDots(filled: pin.count, failed: lastAttemptFailed)

                statusLine

                Spacer()

                bottomControls
                Spacer().frame(height: 22)
            }
            .padding(.horizontal, 24)
            .modifier(ShakeEffect(animatableData: shakeAmount))
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: pin.count)
        .sensoryFeedback(.success, trigger: unlocking) { _, now in now }
        .sensoryFeedback(.error, trigger: lastAttemptFailed) { _, now in now }
        .onAppear {
            startTremor()
            autoFaceIDOnce()
        }
    }

    // MARK: - 밸런스 휠 (잠금 심볼)

    private var wheelStack: some View {
        ZStack {
            // 해제 시 골드 글로우 확산.
            Circle()
                .fill(RadialGradient(colors: [gold.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: 86))
                .frame(width: 150, height: 150)
                .opacity(unlocking ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: unlocking)

            LockBalanceWheel()
                .frame(width: 116, height: 116)
                .rotationEffect(.degrees(tremor))      // idle 미세 진동
                .rotationEffect(.degrees(wheelAngle))  // 자리 bump + 해제 회전

            // 잠금 자물쇠 — 해제되면 사라짐.
            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(goldLight)
                .opacity(unlocking ? 0 : 0.9)
                .animation(.easeOut(duration: 0.3), value: unlocking)
        }
    }

    private func pinDots(filled: Int, failed: Bool) -> some View {
        HStack(spacing: 16) {
            ForEach(0..<PINService.pinLength, id: \.self) { i in
                Circle()
                    .fill(failed ? AppColors.danger
                          : (i < filled ? gold : Color.white.opacity(0.25)))
                    .frame(width: 13, height: 13)
                    .shadow(color: i < filled && !failed ? gold.opacity(0.7) : .clear, radius: 5)
                    .scaleEffect(i < filled && !failed ? 1.05 : 1)
            }
        }
        .animation(.easeOut(duration: 0.18), value: filled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: NSLocalizedString("pin.entry.a11y.progress", comment: ""), filled, PINService.pinLength)))
        .accessibilityValue(failed ? Text(String(localized: "pin.entry.a11y.failed")) : Text(""))
    }

    @ViewBuilder private var statusLine: some View {
        if unlocking {
            Text(String(localized: "pin.entry.unlocked"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(goldLight)
        } else if pinService.isPINLockedOut {
            lockedOutBanner
        } else {
            Text(String(format: String(localized: "pin.entry.remaining"), remaining))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(remaining <= 2 ? Color(red: 0.91, green: 0.6, blue: 0.43)
                                 : Color.white.opacity(0.7))
        }
    }

    private var lockedOutBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppColors.warning)
            Text(String(localized: "pin.entry.locked_out"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white).multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    }

    // MARK: - 하단 컨트롤 (키패드 / Face ID)

    @ViewBuilder private var bottomControls: some View {
        if showKeypad {
            VStack(spacing: 14) {
                PINKeypad(onDigit: append, onDelete: deleteLast, disabled: locked)
                if biometricsAvailable { faceIDButton(compact: true) }
            }
        } else {
            VStack(spacing: 16) {
                if biometricsAvailable { faceIDButton(compact: false) }
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { showKeypad = true }
                } label: {
                    Text(String(localized: "pin.entry.use_pin"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(goldLight)
                        .padding(.vertical, 8).padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func faceIDButton(compact: Bool) -> some View {
        Button { Task { await attemptBiometric() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "faceid").font(.system(size: compact ? 16 : 19, weight: .light))
                Text(String(localized: "pin.entry.use_face_id"))
                    .font(.system(size: compact ? 14 : 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 10 : 13).padding(.horizontal, 22)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(unlocking)
    }

    // MARK: - Face ID

    private static func biometricsReady() -> Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    private func autoFaceIDOnce() {
        guard !didAutoFaceID else { return }
        didAutoFaceID = true
        if biometricsAvailable { Task { await attemptBiometric() } }
    }

    private func attemptBiometric() async {
        guard biometricsAvailable, !unlocking else { return }
        // 생체 인증만(패스코드 폴백 없음) — 실패 시 Face ID 가 재실행되지 않고 PIN 키패드로 폴백.
        if await appLock.unlockBiometricsOnly() {
            playUnlock()
        } else {
            withAnimation(.easeOut(duration: 0.25)) { showKeypad = true }
        }
    }

    // MARK: - 입력 처리

    private func append(_ digit: String) {
        guard !locked, pin.count < PINService.pinLength else { return }
        lastAttemptFailed = false
        pin += digit
        bumpWheel()
        if pin.count == PINService.pinLength { validate() }
    }

    private func deleteLast() {
        guard !locked, !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func validate() {
        if appLock.unlockWithPIN(pin) {
            playUnlock()
        } else {
            playWrong()
        }
    }

    // MARK: - 휠 모션

    /// 자리 입력마다 휠이 조금씩 회전(6자리 = 약 한 바퀴).
    private func bumpWheel() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
            wheelAngle += 360.0 / Double(PINService.pinLength)
        }
    }

    private func startTremor() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { tremor = 2 }
    }

    private func playUnlock() {
        guard !reduceMotion else { onUnlock(); return }
        unlocking = true
        withAnimation(.easeIn(duration: 1.1)) { wheelAngle += 1080 }   // 빠르게 3바퀴
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { onUnlock() }
    }

    private func playWrong() {
        lastAttemptFailed = true
        if !reduceMotion {
            withAnimation(.linear(duration: 0.45)) { shakeAmount += 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pin = ""
            lastAttemptFailed = false
        }
    }
}

/// 가로 흔들림(틀린 PIN) — sin 기반 GeometryEffect. 정수에서 0 으로 복귀.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 9
    var shakes: CGFloat = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes), y: 0))
    }
}

/// 잠금화면용 밸런스 휠 — 골드 그라데이션 림 + 안쪽 링 + 3스포크(타이밍 스크류) + 허브.
private struct LockBalanceWheel: View {
    private let goldLight = Color(red: 0.91, green: 0.79, blue: 0.48)
    private let goldMid   = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let goldDark  = Color(red: 0.60, green: 0.48, blue: 0.18)
    private let hub       = Color(red: 0.11, green: 0.12, blue: 0.22)

    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height)
            let u = s / 100
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            func rect(_ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2) }

            ctx.stroke(Path(ellipseIn: rect(40 * u)),
                       with: .linearGradient(Gradient(colors: [goldLight, goldMid, goldDark]),
                                             startPoint: CGPoint(x: c.x - 40 * u, y: c.y - 40 * u),
                                             endPoint: CGPoint(x: c.x + 40 * u, y: c.y + 40 * u)),
                       lineWidth: 6 * u)
            ctx.stroke(Path(ellipseIn: rect(33 * u)), with: .color(goldMid.opacity(0.35)), lineWidth: 1.5 * u)

            for k in 0..<3 {
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .degrees(Double(k) * 120))
                var spoke = Path()
                spoke.move(to: .zero)
                spoke.addLine(to: CGPoint(x: 0, y: -37 * u))
                g.stroke(spoke, with: .color(goldDark), style: StrokeStyle(lineWidth: 4 * u, lineCap: .round))
                let dr = 3 * u
                g.fill(Path(ellipseIn: CGRect(x: -dr, y: -38 * u - dr, width: dr * 2, height: dr * 2)),
                       with: .color(goldMid))
            }

            ctx.fill(Path(ellipseIn: rect(6.5 * u)), with: .color(goldMid))
            ctx.fill(Path(ellipseIn: rect(2.5 * u)), with: .color(hub))
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
            .overlay(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    PINEntryView(onUnlock: {})
}
