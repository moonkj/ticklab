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
    /// 사용자 요청: DSP 가 실제 검출한 onset timestamps (측정 시작 기준 seconds). 실시간 tic/toc dots.
    var recentOnsetTimes: [Double]? = nil
    /// 측정 시작 wall-clock — onset timestamps 와 함께 60fps viewport 매핑에 사용.
    var measurementStartedAt: Date? = nil
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

                    if running, let bph = lockedBPH, bph > 0 {
                        // 사용자 요청: 직선처럼 평평하면 안 됨 — 적당히 활기있게.
                        //   amplitude h × 0.18, frequency cycle 8개 (1초당 1.6 cycle) 정도.
                        let _ = bph
                        let secondsPerScreen: Double = 5.0
                        let cyclesPerScreen: Double = 8.0
                        let amplitude: Double = Double(h) * 0.18
                        let timePhaseShift = t * 2.0  // 흐름 속도
                        var p = Path()
                        for xi in stride(from: 0.0, through: Double(w), by: 2) {
                            let normX = xi / Double(w)
                            let phase = normX * cyclesPerScreen * 2 * .pi + timePhaseShift
                            let y = Double(mid) + sin(phase) * amplitude
                            if xi == 0 { p.move(to: CGPoint(x: xi, y: y)) }
                            else { p.addLine(to: CGPoint(x: xi, y: y)) }
                        }
                        gc.stroke(p, with: .color(AppColors.primary500), lineWidth: 1.5)
                        // 사용자 요청 (실시간 tic/toc): viewport end = latest onset (envSlice tailTrim lag 보정).
                        //   wallElapsed 사용 시 onset latest 가 항상 ~1.5초 lag → viewport 오른쪽 빈 영역.
                        //   latestOnset 기반 viewport 면 점이 오른쪽 edge 까지 가득.
                        if let onsets = recentOnsetTimes, let latest = onsets.last {
                            let viewEnd = latest
                            let viewStart = viewEnd - secondsPerScreen
                            let yT: CGFloat = mid - 14
                            let yB: CGFloat = mid + 14
                            for (i, ts) in onsets.enumerated() where ts >= viewStart && ts <= viewEnd {
                                let progress = (ts - viewStart) / secondsPerScreen  // 0...1
                                let x = CGFloat(progress) * w
                                let isTic = (i % 2 == 0)
                                let y = isTic ? yT : yB
                                gc.fill(
                                    Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                                    with: .color(isTic ? AppColors.success : AppColors.accent)
                                )
                            }
                        }
                    } else if running {
                        // 사용자 요청: 측정은 시작됐지만 lock 아직 → dashed line ("---------- 으로 나와야") .
                        //   움직이는 dash offset 으로 측정 중임을 시각적으로 표시.
                        let dashLen: CGFloat = 8
                        let gapLen: CGFloat = 6
                        let cycle = dashLen + gapLen
                        let off = CGFloat(t * 30).truncatingRemainder(dividingBy: cycle)
                        var x = -cycle + off
                        var dashes = Path()
                        while x < w {
                            dashes.move(to: CGPoint(x: max(0, x), y: mid))
                            dashes.addLine(to: CGPoint(x: min(w, x + dashLen), y: mid))
                            x += cycle
                        }
                        gc.stroke(dashes, with: .color(AppColors.primary500.opacity(0.45)), lineWidth: 1.6)
                    } else {
                        // idle / .requestingPermission / 측정 시작 전 — 정적 가는 baseline.
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
