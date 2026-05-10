import SwiftUI

/// 측정 중 실시간 파형 시각화. samples 배열의 [-1, 1] 값을 horizontal bar 로 표시.
/// TimelineView(.animation) 으로 60fps 타깃, frame budget 16ms 초과 시 fallback 권고 (CLAUDE.md Hard Rule #4).
struct LiveWaveformView: View {
    let samples: [Float]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
            Canvas { context, size in
                guard !samples.isEmpty else { return }
                let midY = size.height / 2
                let count = samples.count
                let columnWidth = size.width / CGFloat(count)
                var path = Path()
                for (idx, sample) in samples.enumerated() {
                    let x = CGFloat(idx) * columnWidth
                    let amp = CGFloat(max(-1, min(1, sample))) * (size.height * 0.45)
                    path.move(to: CGPoint(x: x, y: midY - amp))
                    path.addLine(to: CGPoint(x: x, y: midY + amp))
                }
                context.stroke(path, with: .color(AppColors.primary), lineWidth: 1.5)
                // baseline
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: midY))
                baseline.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(baseline, with: .color(AppColors.border), lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    let demo: [Float] = (0..<200).map { Float(sin(Double($0) * 0.3)) * 0.5 }
    return LiveWaveformView(samples: demo).frame(height: 120).padding()
}
