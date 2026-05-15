import SwiftUI

/// 디자인 SSOT components.jsx LiveWaveform port — Canvas requestAnimationFrame 시뮬레이션.
/// 시계 tic/toc 시각화 — primary-700 sin curve + tic (green) / toc (gold) dots.
/// Onboarding FirstMeasurement / Production MeasurementView 둘 다 동일 visual.
struct LiveWaveformCanvas: View {
    var running: Bool = true
    /// raw waveform samples (-1...1). nil 이면 합성 sin 사용.
    var samples: [Float]? = nil
    /// Round 158: detected BPH (locked). nil 이면 검출 중 모드 (flat line + 검색 indicator).
    /// non-nil 이면 locked 모드 (tic/toc dots at expected intervals).
    var lockedBPH: Int? = nil
    var showProInfo: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Round 122 (이소라 H2 / Hard Rule 4): 60fps 상한 명시 — ProMotion 120fps 예산 초과 방지.
            TimelineView(.animation(minimumInterval: 1.0/60.0, paused: false)) { ctx in
                Canvas { gc, size in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let w = size.width
                    let h = size.height
                    let mid = h / 2

                    // Grid lines (4 horizontal).
                    for y in stride(from: 0.0, through: h, by: h / 4) {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                        gc.stroke(p, with: .color(AppColors.primary500.opacity(0.12)), lineWidth: 1)
                    }

                    if running {
                        // Round 170 (사용자 요청: 측정 중 그래프 부드럽게):
                        // lock 여부와 무관하게 항상 부드러운 sin curve. BPH lock 잡히면 dots 추가.
                        let beatsPerSec: Double = lockedBPH.map { Double($0) / 3600.0 } ?? 8.0
                        let secondsPerScreen: Double = 5.0
                        let speed = w / secondsPerScreen
                        let off = t * speed
                        var p = Path()
                        for xi in stride(from: 0.0, through: Double(w), by: 2) {
                            let timeAtX = (xi - Double(off).truncatingRemainder(dividingBy: Double(w))) / speed
                            let phase = timeAtX * beatsPerSec * 2 * .pi
                            let env = exp(-pow(sin(phase * 0.5) - 0.3, 2) * 4)
                            let y = Double(mid) + sin(phase) * env * Double(h) * 0.35
                            if xi == 0 { p.move(to: CGPoint(x: xi, y: y)) }
                            else { p.addLine(to: CGPoint(x: xi, y: y)) }
                        }
                        gc.stroke(p, with: .color(AppColors.primary500), lineWidth: 1.6)
                        // tic / toc dots — BPH lock 잡힌 경우에만.
                        if let bph = lockedBPH, bph > 0 {
                            let dotSpacing = speed / beatsPerSec
                            let pairWidth = dotSpacing * 2
                            let totalPairs = Int(w / pairWidth) + 1
                            for i in 0..<totalPairs {
                                let baseX = Double(i) * pairWidth - off.truncatingRemainder(dividingBy: pairWidth)
                                let x: CGFloat = baseX < 0 ? CGFloat(baseX) + w : CGFloat(baseX)
                                let yT: CGFloat = mid - 14
                                let yB: CGFloat = mid + 14
                                gc.fill(
                                    Path(ellipseIn: CGRect(x: x - 3, y: yT - 3, width: 6, height: 6)),
                                    with: .color(AppColors.success)
                                )
                                gc.fill(
                                    Path(ellipseIn: CGRect(x: x + CGFloat(dotSpacing) - 3, y: yB - 3, width: 6, height: 6)),
                                    with: .color(AppColors.accent)
                                )
                            }
                        }
                    } else {
                        // Round 170 (사용자 보고: "측정 시작 시 옛 노이즈 그래프 나옴"):
                        // 이전 synthetic sin + dots 가 noise 처럼 보임 → 깔끔한 baseline 으로 대체.
                        // idle / .requestingPermission / 측정 시작 직후 모두 동일.
                        var baseline = Path()
                        baseline.move(to: CGPoint(x: 0, y: mid))
                        baseline.addLine(to: CGPoint(x: w, y: mid))
                        gc.stroke(baseline, with: .color(AppColors.primary500.opacity(0.2)), lineWidth: 1)
                    }
                }
            }
            // tic/toc legend (bottom-right).
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Circle().fill(AppColors.success).frame(width: 6, height: 6)
                    Text("tic")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.ink2)
                }
                HStack(spacing: 4) {
                    Circle().fill(AppColors.accent).frame(width: 6, height: 6)
                    Text("toc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.ink2)
                }
            }
            .padding(.bottom, 8)
            .padding(.trailing, 12)
        }
        .background(AppColors.paper2)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack {
        LiveWaveformCanvas(running: true)
            .frame(height: 170)
        LiveWaveformCanvas(running: true, samples: [0.1, 0.2], lockedBPH: 28800)
            .frame(height: 170)
        LiveWaveformCanvas(running: true, samples: [0.1, 0.2], lockedBPH: nil)
            .frame(height: 170)
    }
    .padding()
    .background(AppColors.paper0)
}
