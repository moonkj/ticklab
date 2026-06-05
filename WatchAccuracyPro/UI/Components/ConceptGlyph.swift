import SwiftUI

/// 의미 기반 아이콘 리졸버 — SF Symbol 이름을 받아 시계 컨셉 커스텀 벡터로 매핑,
/// 매핑 없으면 SF Symbol 폴백. `Image(systemName:)` 드롭인 대체.
///
/// 색: `color` 미지정(nil)이면 `.foreground` 로 **주변 foregroundStyle 을 상속**(SF Symbol 처럼).
/// 지정하면 그 색 사용. 크기는 `size` 프레임으로 고정.
///
/// 원칙: 브랜드/피처/콘텐츠 식별 아이콘만 커스텀화하고, 시스템 관용 affordance
/// (chevron·xmark·plus·trash·share·info·checkmark·lock·gear 등)와 AI(sparkles)는 SF 유지.
struct ConceptGlyph: View {
    let systemName: String
    var size: CGFloat = 26
    /// nil = 주변 foreground 색 상속. 지정 시 해당 색 강제.
    var color: Color? = nil

    private var lw: CGFloat { max(1.2, size * 0.075) }
    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round) }
    private let barHeights: [CGFloat] = [0.4, 0.62, 0.86]
    /// Path/Shape 채움·선 스타일 — 색 상속 또는 강제.
    private var fill: AnyShapeStyle { color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground) }
    /// 컴포넌트 아이콘(밸런스 휠/다이얼)용 구체 색 — 상속 불가라 기본 ink2.
    private var solidColor: Color { color ?? AppColors.ink2 }

    var body: some View {
        glyph.frame(width: size, height: size)
    }

    @ViewBuilder
    private var glyph: some View {
        switch systemName {
        // 측정·무브먼트 → 밸런스 휠
        case "waveform.path.ecg", "waveform", "waveform.path", "mic", "mic.circle",
             "metronome", "stopwatch", "timer", "scope", "dot.radiowaves.left.and.right":
            BalanceWheelIcon(size: size, color: solidColor, holeColor: AppColors.paper1)
        // 시계·시간 → 다이얼+핸즈
        case "watch.analog", "clock":
            DialHandsIcon(size: size, color: solidColor)
        // 애플워치/케이스 → 워치 케이스
        case "applewatch", "applewatch.watchface":
            watchCase
        // 커뮤니티 → 인물
        case "person.2.fill", "person.2.circle", "person.2", "person.crop.circle":
            people
        // 좋아요 → 하트 (인스타식: 좋아요=채움(빨강), 미좋아요=외곽선)
        case "heart.fill":
            Heart().fill(fill).frame(width: size * 0.7, height: size * 0.64)
        case "heart":
            Heart().stroke(fill, style: stroke).frame(width: size * 0.66, height: size * 0.6)
        // 별·하이라이트 → 별 (fill/outline 2-state 유지)
        case "star.fill", "sparkle":
            StarShape(points: 5).fill(fill).frame(width: size * 0.82, height: size * 0.82)
        case "star":
            StarShape(points: 5).stroke(fill, style: stroke).frame(width: size * 0.78, height: size * 0.78)
        // 인증·착용 세일 → 갈래 세일 + 체크 (fill/outline 2-state)
        case "checkmark.seal.fill":
            sealCheck(filled: true)
        case "checkmark.seal":
            sealCheck(filled: false)
        // 저널 → 책
        case "text.alignleft", "book.closed", "book":
            book
        // 뉴스 → 신문
        case "newspaper", "newspaper.fill":
            newspaperGlyph
        // 선물(Wrapped) → 선물상자
        case "gift", "gift.fill":
            gift
        // 메달(브랜드리그) → 리본 메달
        case "medal", "medal.fill", "rosette":
            medal
        // 자기장 → 말굽자석
        case "magnet", "bolt.horizontal", "bolt.horizontal.fill":
            magnet
        // 뽑기 → 주사위
        case "dice", "dice.fill":
            dice
        // 운세 → 초승달+별
        case "crystal", "moon.stars", "moon.stars.fill":
            fortune
        // 불꽃(스트릭) → 불꽃
        case "flame", "flame.fill":
            Flame().fill(fill).frame(width: size * 0.6, height: size * 0.8)
        // 통계(막대) → 막대
        case "chart.bar.fill", "chart.bar.xaxis", "chart.bar", "chart.pie":
            bars
        // 통계(추세선) → 라인차트
        case "chart.line.uptrend.xyaxis", "chart.xyaxis.line":
            lineChart
        // 사진·카메라 → 카메라
        case "camera", "camera.fill", "photo.on.rectangle", "photo.on.rectangle.angled", "photo":
            camera
        // 영상(유튜브) → 빨간 유튜브 플레이(2색 고정).
        case "play.rectangle", "play.rectangle.fill":
            youtubePlay
        // 일반 재생(녹음 등) → 모노 플레이.
        case "play.circle", "play.circle.fill":
            play
        // 정비 → 코그
        case "wrench.and.screwdriver", "wrench.and.screwdriver.fill", "wrench.adjustable":
            CogShape(teeth: 9, innerRatio: 0.7).fill(fill).frame(width: size * 0.82, height: size * 0.82)
                .overlay(Circle().fill(AppColors.paper1).frame(width: size * 0.28, height: size * 0.28))
        // 트로피 → 우승컵
        case "trophy", "trophy.fill":
            trophy
        // 타깃 → 동심원
        case "target":
            ZStack {
                Circle().stroke(fill, style: stroke).frame(width: size * 0.86, height: size * 0.86)
                Circle().stroke(fill, style: stroke).frame(width: size * 0.5, height: size * 0.5)
                Circle().fill(fill).frame(width: size * 0.16, height: size * 0.16)
            }
        // 북마크 → 리본
        case "bookmark", "bookmark.fill":
            bookmark
        // 태그 → 라벨
        case "tag", "tag.fill":
            tag
        // 배터리 → 배터리
        case "battery.100", "battery.75", "battery.50", "battery.25", "battery.0":
            battery
        // 글로브 → 경위선 지구본
        case "globe":
            ZStack {
                Circle().stroke(fill, style: stroke).frame(width: size * 0.84, height: size * 0.84)
                Ellipse().stroke(fill, lineWidth: lw * 0.7).frame(width: size * 0.4, height: size * 0.84)
                Capsule().fill(fill).frame(width: size * 0.84, height: lw * 0.7)
            }
        default:
            Image(systemName: systemName)
                .font(.system(size: size, weight: .light))
                .foregroundStyle(fill)
        }
    }

    // MARK: - Composite glyphs

    private var people: some View {
        ZStack {
            personMini.scaleEffect(0.82).offset(x: size * 0.17, y: size * 0.03)
            personMini.offset(x: -size * 0.12)
        }
    }

    private var personMini: some View {
        ZStack {
            Circle().fill(fill).frame(width: size * 0.26, height: size * 0.26).offset(y: -size * 0.16)
            Circle().fill(fill).frame(width: size * 0.44, height: size * 0.44)
                .mask(Rectangle().frame(width: size * 0.44, height: size * 0.24).offset(y: -size * 0.1))
                .offset(y: size * 0.14)
        }
    }

    private var book: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .stroke(fill, style: stroke)
                .frame(width: size * 0.6, height: size * 0.76)
            Rectangle().fill(fill).frame(width: lw, height: size * 0.76).offset(x: -size * 0.15)
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(fill).frame(width: size * 0.22, height: lw * 0.8)
                    .offset(x: size * 0.06, y: CGFloat(i) * size * 0.16 - size * 0.06)
            }
        }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: size * 0.1) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(fill).frame(width: size * 0.15, height: size * barHeights[i])
            }
        }
        .frame(width: size, height: size * 0.86, alignment: .bottom)
    }

    private var lineChart: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size * 0.16, y: size * 0.16))
                p.addLine(to: CGPoint(x: size * 0.16, y: size * 0.82))
                p.addLine(to: CGPoint(x: size * 0.86, y: size * 0.82))
            }.stroke(fill, style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round, lineJoin: .round))
            Path { p in
                p.move(to: CGPoint(x: size * 0.24, y: size * 0.66))
                p.addLine(to: CGPoint(x: size * 0.44, y: size * 0.5))
                p.addLine(to: CGPoint(x: size * 0.58, y: size * 0.58))
                p.addLine(to: CGPoint(x: size * 0.82, y: size * 0.26))
            }.stroke(fill, style: stroke)
            Triangle().fill(fill).frame(width: size * 0.16, height: size * 0.16)
                .rotationEffect(.degrees(38)).offset(x: size * 0.31, y: -size * 0.22)
        }
    }

    private var camera: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .stroke(fill, style: stroke).frame(width: size * 0.82, height: size * 0.6)
            Capsule().fill(fill).frame(width: size * 0.22, height: size * 0.1).offset(x: -size * 0.16, y: -size * 0.33)
            Circle().stroke(fill, style: stroke).frame(width: size * 0.28, height: size * 0.28).offset(y: size * 0.02)
        }
    }

    private var play: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .stroke(fill, style: stroke).frame(width: size * 0.82, height: size * 0.6)
            Triangle().fill(fill).frame(width: size * 0.2, height: size * 0.24).rotationEffect(.degrees(90))
        }
    }

    /// 유튜브 로고형 — 빨간 둥근 사각형(가로 squircle) + 흰 우향 플레이 삼각형(광학 중앙).
    /// 색 고정(빨강/흰색) — 어디서나 유튜브 식별.
    private var youtubePlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color(red: 0.94, green: 0.11, blue: 0.13))
                .frame(width: size * 0.9, height: size * 0.64)
            // 우향 삼각형은 무게중심이 좌측 1/3 → 살짝 오른쪽으로 보정해 박스 중앙에 보이게.
            PlayTriangle()
                .fill(.white)
                .frame(width: size * 0.24, height: size * 0.27)
                .offset(x: size * 0.035)
        }
        .frame(width: size, height: size)
    }

    private var watchCase: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .stroke(fill, style: stroke).frame(width: size * 0.56, height: size * 0.66)
            Capsule().fill(fill).frame(width: size * 0.3, height: size * 0.12).offset(y: -size * 0.4)
            Capsule().fill(fill).frame(width: size * 0.3, height: size * 0.12).offset(y: size * 0.4)
            Circle().stroke(fill, lineWidth: lw * 0.7).frame(width: size * 0.3, height: size * 0.3)
            Circle().fill(fill).frame(width: size * 0.07, height: size * 0.07)
            Capsule().fill(fill).frame(width: size * 0.07, height: size * 0.1).offset(x: size * 0.3)
        }
    }

    private var trophy: some View {
        let w = size, h = size
        // 전부 절대좌표(0..size). 손잡이·기둥·받침은 .position 으로 같은 공간에 배치.
        return ZStack {
            // 양옆 손잡이 — 컵에 붙는 작은 곡선.
            Path { p in
                p.move(to: CGPoint(x: w * 0.31, y: h * 0.20))
                p.addCurve(to: CGPoint(x: w * 0.33, y: h * 0.33),
                           control1: CGPoint(x: w * 0.18, y: h * 0.21), control2: CGPoint(x: w * 0.19, y: h * 0.33))
            }.stroke(fill, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: w * 0.69, y: h * 0.20))
                p.addCurve(to: CGPoint(x: w * 0.67, y: h * 0.33),
                           control1: CGPoint(x: w * 0.82, y: h * 0.21), control2: CGPoint(x: w * 0.81, y: h * 0.33))
            }.stroke(fill, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            // 컵 — 넓은 윗변에서 좁아져 둥근 바닥.
            Path { p in
                p.move(to: CGPoint(x: w * 0.30, y: h * 0.16))
                p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.16))
                p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.34))
                p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.50), control: CGPoint(x: w * 0.60, y: h * 0.48))
                p.addQuadCurve(to: CGPoint(x: w * 0.38, y: h * 0.34), control: CGPoint(x: w * 0.40, y: h * 0.48))
                p.closeSubpath()
            }.fill(fill)
            // 기둥 + 2단 받침 (절대 위치).
            Rectangle().fill(fill).frame(width: lw * 1.3, height: h * 0.10).position(x: w * 0.5, y: h * 0.56)
            Capsule().fill(fill).frame(width: w * 0.24, height: lw * 1.3).position(x: w * 0.5, y: h * 0.64)
            Capsule().fill(fill).frame(width: w * 0.42, height: lw * 1.5).position(x: w * 0.5, y: h * 0.72)
        }
        .frame(width: w, height: h)
    }

    private var bookmark: some View {
        Path { p in
            p.move(to: CGPoint(x: size * 0.3, y: size * 0.16))
            p.addLine(to: CGPoint(x: size * 0.7, y: size * 0.16))
            p.addLine(to: CGPoint(x: size * 0.7, y: size * 0.84))
            p.addLine(to: CGPoint(x: size * 0.5, y: size * 0.66))
            p.addLine(to: CGPoint(x: size * 0.3, y: size * 0.84))
            p.closeSubpath()
        }.stroke(fill, style: stroke)
    }

    private var tag: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size * 0.5, y: size * 0.2))
                p.addLine(to: CGPoint(x: size * 0.82, y: size * 0.5))
                p.addLine(to: CGPoint(x: size * 0.5, y: size * 0.8))
                p.addLine(to: CGPoint(x: size * 0.2, y: size * 0.8))
                p.addLine(to: CGPoint(x: size * 0.2, y: size * 0.5))
                p.closeSubpath()
            }.stroke(fill, style: stroke)
            Circle().fill(fill).frame(width: size * 0.1, height: size * 0.1).offset(x: -size * 0.04, y: size * 0.05)
        }
    }

    private var battery: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .stroke(fill, style: stroke).frame(width: size * 0.74, height: size * 0.4)
            Capsule().fill(fill).frame(width: size * 0.05, height: size * 0.16).offset(x: size * 0.42)
            RoundedRectangle(cornerRadius: size * 0.04).fill(fill).frame(width: size * 0.5, height: size * 0.22).offset(x: -size * 0.08)
        }
    }

    private var gift: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06, style: .continuous).stroke(fill, style: stroke)
                .frame(width: size * 0.66, height: size * 0.48).offset(y: size * 0.14)
            Rectangle().fill(fill).frame(width: lw, height: size * 0.48).offset(y: size * 0.14)
            RoundedRectangle(cornerRadius: size * 0.04, style: .continuous).stroke(fill, style: stroke)
                .frame(width: size * 0.74, height: size * 0.16).offset(y: -size * 0.16)
            Circle().stroke(fill, style: stroke).frame(width: size * 0.16, height: size * 0.16).offset(x: -size * 0.1, y: -size * 0.3)
            Circle().stroke(fill, style: stroke).frame(width: size * 0.16, height: size * 0.16).offset(x: size * 0.1, y: -size * 0.3)
        }
    }

    private var medal: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size * 0.38, y: size * 0.06)); p.addLine(to: CGPoint(x: size * 0.46, y: size * 0.42))
                p.move(to: CGPoint(x: size * 0.62, y: size * 0.06)); p.addLine(to: CGPoint(x: size * 0.54, y: size * 0.42))
            }.stroke(fill, style: stroke)
            CogShape(teeth: 10, innerRatio: 0.86).fill(fill).frame(width: size * 0.5, height: size * 0.5).offset(y: size * 0.18)
            StarShape(points: 5).fill(AppColors.paper1).frame(width: size * 0.22, height: size * 0.22).offset(y: size * 0.18)
        }
    }

    private var newspaperGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06, style: .continuous).stroke(fill, style: stroke)
                .frame(width: size * 0.74, height: size * 0.66)
            Rectangle().fill(fill).frame(width: size * 0.48, height: lw * 1.1).offset(x: -size * 0.06, y: -size * 0.18)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(fill).frame(width: size * 0.2, height: lw * 0.7)
                    .offset(x: -size * 0.16, y: CGFloat(i) * size * 0.1 - size * 0.02)
            }
            Rectangle().stroke(fill, lineWidth: lw * 0.7).frame(width: size * 0.18, height: size * 0.2).offset(x: size * 0.18, y: size * 0.04)
        }
    }

    private var magnet: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size * 0.28, y: size * 0.8))
                p.addLine(to: CGPoint(x: size * 0.28, y: size * 0.42))
                p.addArc(center: CGPoint(x: size * 0.5, y: size * 0.42), radius: size * 0.22,
                         startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: CGPoint(x: size * 0.72, y: size * 0.8))
            }.stroke(fill, style: StrokeStyle(lineWidth: lw * 1.7, lineCap: .butt))
            Rectangle().fill(fill).frame(width: lw * 1.7, height: size * 0.1).offset(x: -size * 0.22, y: size * 0.76)
            Rectangle().fill(fill).frame(width: lw * 1.7, height: size * 0.1).offset(x: size * 0.22, y: size * 0.76)
        }
    }

    private var dice: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).stroke(fill, style: stroke)
                .frame(width: size * 0.66, height: size * 0.66)
            ForEach(0..<5, id: \.self) { i in
                let pos: [(CGFloat, CGFloat)] = [(-0.16, -0.16), (0.16, -0.16), (0, 0), (-0.16, 0.16), (0.16, 0.16)]
                Circle().fill(fill).frame(width: size * 0.1, height: size * 0.1)
                    .offset(x: size * pos[i].0, y: size * pos[i].1)
            }
        }
    }

    private var fortune: some View {
        ZStack {
            Sparkle().fill(fill).frame(width: size * 0.72, height: size * 0.72)
            Sparkle().fill(fill).frame(width: size * 0.24, height: size * 0.24)
                .offset(x: size * 0.3, y: -size * 0.28)
        }
    }

    private func sealCheck(filled: Bool) -> some View {
        ZStack {
            if filled {
                CogShape(teeth: 11, innerRatio: 0.86).fill(fill)
                CheckMark().stroke(AppColors.paper1, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.32, height: size * 0.26)
            } else {
                CogShape(teeth: 11, innerRatio: 0.86).stroke(fill, style: stroke)
                CheckMark().stroke(fill, style: stroke).frame(width: size * 0.32, height: size * 0.26)
            }
        }
        .frame(width: size * 0.92, height: size * 0.92)
    }
}

/// 우향 플레이 삼각형 — 좌변 full height + 우중앙 apex. (회전 없이 그려 무게중심 보정이 쉬움)
struct PlayTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 4각 반짝임(✦) — 오목한 변으로 우아한 트윙클. 운세/매직 글리프용.
struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let R = min(r.width, r.height) / 2
        let k = R * 0.16   // 컨트롤 인셋 → 오목한 변
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - R))
        p.addQuadCurve(to: CGPoint(x: c.x + R, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + R), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - R, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R), control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}
