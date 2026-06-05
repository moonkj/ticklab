import SwiftUI

// MARK: - Badge glyphs (업적 뱃지 커스텀 벡터 아이콘)
//
// 이모지 대신 시계 컨셉의 모노라인 벡터 글리프로 업적 뱃지를 표시한다.
// badge.id 로 매핑하며, 이모지(badge.emoji)는 장착/커뮤니티 식별용으로 그대로 유지된다(표시만 교체).
// 단색(color) 1개로 stroke/fill 을 통일 — 카드(흰색)·셀(레어도 색) 어디서나 또렷.

struct BadgeGlyph: View {
    let id: String
    var size: CGFloat = 34
    var color: Color = AppColors.ink1

    private var lw: CGFloat { max(1.2, size * 0.075) }
    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round) }

    var body: some View {
        glyph
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // 다이얼 베이스 링(여러 글리프 공통).
    private func ring(_ ratio: CGFloat = 0.92) -> some View {
        Circle().stroke(color, style: stroke).frame(width: size * ratio, height: size * ratio)
    }

    @ViewBuilder
    private var glyph: some View {
        switch id {
        // ── 측정 횟수/진행 ─────────────────────────────────────────
        case "b10":  // 첫 측정 — 다이얼 + 체크
            ZStack { ring(); CheckMark().stroke(color, style: stroke).frame(width: size*0.42, height: size*0.34) }
        case "b17":  // 측정 10회 — 게이지(반원 + 바늘)
            gauge(fraction: 0.55)
        case "b18":  // 측정 50회 — 스톱워치
            stopwatch
        case "b8":   // 한 시계 100회 — 게이지 풀
            gauge(fraction: 0.92)
        case "b19":  // 365회 — 로열 크라운
            royalCrown
        // ── 시계 종류/기능 ─────────────────────────────────────────
        case "b7":   // GMT/여행 — 지구본(자오선 + 적도)
            ZStack {
                ring()
                Ellipse().stroke(color, lineWidth: lw*0.7).frame(width: size*0.42, height: size*0.82)
                Capsule().fill(color).frame(width: size*0.82, height: lw*0.7)
            }
        case "b1":   // 다이버 — 회전 베젤(12시 삼각형) + 파도
            ZStack {
                ring()
                Triangle().fill(color).frame(width: size*0.18, height: size*0.16).offset(y: -size*0.42)
                Wave().stroke(color, style: stroke).frame(width: size*0.5, height: size*0.18).offset(y: size*0.06)
            }
        case "b6":   // 문페이즈 — 보름달 + 크레이터
            ZStack {
                Circle().fill(color).frame(width: size*0.78, height: size*0.78)
                Circle().fill(AppColors.paper1.opacity(0.0)) // spacer
            }.overlay(craters)
        case "b24":  // 자정 측정 — 초승달 + 별
            ZStack {
                Crescent().fill(color).frame(width: size*0.66, height: size*0.66)
                StarShape(points: 4).fill(color).frame(width: size*0.22, height: size*0.22).offset(x: size*0.26, y: -size*0.24)
            }
        case "b4":   // 새벽 측정 — 일출(반해 + 지평선 + 광선)
            sunrise
        case "b16":  // 야간 측정 — 초승달
            Crescent().fill(color).frame(width: size*0.7, height: size*0.7)
        // ── 정확도/품질 ───────────────────────────────────────────
        case "b13":  // COSC — 인증 세일
            ZStack {
                CogShape(teeth: 12, innerRatio: 0.84).fill(color).frame(width: size*0.92, height: size*0.92)
                CheckMark().stroke(AppColors.paper1, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                    .frame(width: size*0.34, height: size*0.28)
            }
        case "b14":  // 등급 A — 별
            StarShape(points: 5).fill(color).frame(width: size*0.86, height: size*0.86)
        case "b15":  // 비트 에러 완벽 — 튜닝포크
            tuningFork
        case "b21":  // 크로노그래프 — 다이얼 + 서브다이얼 + 푸셔 2
            chronograph
        // ── 컬렉션 규모/다양성 ────────────────────────────────────
        case "b5":   // 7개 브랜드 — 기어
            ZStack {
                CogShape(teeth: 9, innerRatio: 0.74).fill(color).frame(width: size*0.92, height: size*0.92)
                Circle().fill(AppColors.paper1).frame(width: size*0.30, height: size*0.30)
                Circle().stroke(color, lineWidth: lw*0.8).frame(width: size*0.30, height: size*0.30)
            }
        case "b9":   // 5개 브랜드 — 겹친 다이얼 3
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle().stroke(color, style: stroke).frame(width: size*0.5, height: size*0.5)
                        .offset(x: CGFloat(i-1)*size*0.22, y: CGFloat(i-1)*size*0.1)
                }
            }
        case "b2":   // 5개 등록 — 트로피
            trophy
        case "b22":  // 10개 등록 — 메달(원 + 리본)
            medal
        // ── 착용/기록 ─────────────────────────────────────────────
        case "b3":   // 최장 착용 — 타깃
            ZStack {
                ring(0.92); ring(0.58); Circle().fill(color).frame(width: size*0.16, height: size*0.16)
            }
        case "b11":  // 저널 50 — 펼친 책
            openBook
        case "b25":  // 저널 7일 연속 — 책 + 북마크
            ZStack {
                openBook
                Rectangle().fill(color).frame(width: size*0.12, height: size*0.4).offset(x: size*0.22, y: -size*0.05)
            }
        // ── 빈티지/헤리티지 ───────────────────────────────────────
        case "b20":  // 빈티지 — 회중시계(원 + 보우 + 크라운)
            pocketWatch
        case "b32":  // 빈티지 5개 — 클래식 기둥
            column
        // ── 디테일/심화 ───────────────────────────────────────────
        case "b23":  // 칼리버 입력 — 무브먼트 브릿지
            movement
        case "b26":  // 장시간 측정 25 — 모래시계
            hourglass
        case "b27":  // 같은날 2회 10일 — 순환 화살표
            cycleArrows
        case "b28":  // 감정 스펙트럼 — 다이얼 안 하트
            ZStack { ring(); Heart().fill(color).frame(width: size*0.4, height: size*0.36) }
        case "b29":  // 고진폭 — 진폭 호
            ZStack {
                Circle().trim(from: 0.08, to: 0.42).stroke(color, style: stroke)
                    .frame(width: size*0.86, height: size*0.86).rotationEffect(.degrees(180))
                Capsule().fill(color).frame(width: lw*0.9, height: size*0.34).rotationEffect(.degrees(-30))
                Circle().fill(color).frame(width: size*0.14, height: size*0.14)
            }
        case "b30":  // BPH 종류 — 파형(오실로)
            ZStack { ring(); Wave().stroke(color, style: stroke).frame(width: size*0.6, height: size*0.3) }
        case "b31":  // 4계절 — 잎사귀
            Leaf().fill(color).frame(width: size*0.7, height: size*0.8)
        case "b12":  // 모두 획득 — 보석(사파이어 크리스탈)
            gem
        // ── 커뮤니티 ──────────────────────────────────────────────
        case "b33":  // 첫 게시 — 액자
            ZStack {
                RoundedRectangle(cornerRadius: size*0.08).stroke(color, style: stroke).frame(width: size*0.74, height: size*0.62)
                Circle().fill(color).frame(width: size*0.12, height: size*0.12).offset(x: -size*0.12, y: -size*0.08)
                Triangle().fill(color).frame(width: size*0.4, height: size*0.22).offset(y: size*0.12)
            }
        case "b34":  // 좋아요 100 줌 — 엄지업
            thumbsUp
        case "b35":  // 좋아요 100 받음 — 불꽃
            Flame().fill(color).frame(width: size*0.6, height: size*0.8)
        case "b36":  // 게시 100 — 카메라
            camera
        case "b37":  // 팔로잉 50 — 3노드 네트워크(연결)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: size*0.5, y: size*0.28))
                    p.addLine(to: CGPoint(x: size*0.26, y: size*0.7))
                    p.addLine(to: CGPoint(x: size*0.74, y: size*0.7))
                    p.closeSubpath()
                }.stroke(color, style: stroke)
                Circle().fill(color).frame(width: size*0.22, height: size*0.22).position(x: size*0.5, y: size*0.28)
                Circle().fill(color).frame(width: size*0.22, height: size*0.22).position(x: size*0.26, y: size*0.7)
                Circle().fill(color).frame(width: size*0.22, height: size*0.22).position(x: size*0.74, y: size*0.7)
            }
            .frame(width: size, height: size)
        case "b38":  // 팔로워 100 — 메가폰
            megaphone
        default:
            ring()  // 폴백 — 다이얼 링
        }
    }

    // MARK: - Composite glyphs

    private func gauge(fraction: CGFloat) -> some View {
        ZStack {
            Circle().trim(from: 0.5, to: 1.0).stroke(color, style: stroke)
                .frame(width: size*0.86, height: size*0.86)
            // 바늘
            Capsule().fill(color).frame(width: lw*0.9, height: size*0.34)
                .offset(y: -size*0.12)
                .rotationEffect(.degrees(-90 + Double(fraction) * 180))
            Circle().fill(color).frame(width: size*0.13, height: size*0.13).offset(y: size*0.02)
        }
        .offset(y: size*0.12)
    }

    private var stopwatch: some View {
        ZStack {
            ring(0.84)
            // 크라운/푸셔
            Capsule().fill(color).frame(width: size*0.16, height: size*0.1).offset(y: -size*0.46)
            Capsule().fill(color).frame(width: size*0.1, height: size*0.08).offset(x: size*0.3, y: -size*0.34).rotationEffect(.degrees(45))
            // 핸드
            Capsule().fill(color).frame(width: lw*0.9, height: size*0.3).offset(y: -size*0.07).rotationEffect(.degrees(28))
            Circle().fill(color).frame(width: size*0.1, height: size*0.1)
        }
    }

    private var royalCrown: some View {
        ZStack {
            CrownPeaks().fill(color).frame(width: size*0.8, height: size*0.5).offset(y: -size*0.04)
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(color).frame(width: size*0.1, height: size*0.1)
                    .offset(x: CGFloat(i-1)*size*0.28, y: -size*0.30)
            }
            RoundedRectangle(cornerRadius: size*0.04).fill(color).frame(width: size*0.72, height: size*0.12).offset(y: size*0.24)
        }
    }

    private var craters: some View {
        ZStack {
            Circle().fill(AppColors.paper1.opacity(0.0))
        }
        .overlay(
            ZStack {
                Circle().fill(AppColors.paper1).frame(width: size*0.16, height: size*0.16).offset(x: -size*0.1, y: -size*0.08)
                Circle().fill(AppColors.paper1).frame(width: size*0.1, height: size*0.1).offset(x: size*0.14, y: size*0.04)
                Circle().fill(AppColors.paper1).frame(width: size*0.08, height: size*0.08).offset(x: -size*0.04, y: size*0.16)
            }
        )
    }

    private var sunrise: some View {
        ZStack {
            // 광선 — 반해 위로 부채꼴.
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(color).frame(width: lw*0.75, height: size*0.13)
                    .offset(y: -size*0.30)
                    .rotationEffect(.degrees(Double(i-2) * 30))
            }
            // 반해 — 위쪽 반원(mask), 지평선에 얹힘.
            Circle().fill(color).frame(width: size*0.44, height: size*0.44)
                .mask(Rectangle().frame(width: size*0.44, height: size*0.22).offset(y: -size*0.11))
                .offset(y: size*0.12)
            // 지평선 — 반해 밑변과 동일 y.
            Capsule().fill(color).frame(width: size*0.84, height: lw).offset(y: size*0.12)
        }
    }

    private var tuningFork: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size*0.34, y: size*0.1)); p.addLine(to: CGPoint(x: size*0.34, y: size*0.5))
                p.move(to: CGPoint(x: size*0.66, y: size*0.1)); p.addLine(to: CGPoint(x: size*0.66, y: size*0.5))
                p.addArc(center: CGPoint(x: size*0.5, y: size*0.5), radius: size*0.16, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                p.move(to: CGPoint(x: size*0.5, y: size*0.66)); p.addLine(to: CGPoint(x: size*0.5, y: size*0.9))
            }.stroke(color, style: stroke)
        }
    }

    private var chronograph: some View {
        ZStack {
            ring(0.86)
            Circle().stroke(color, lineWidth: lw*0.7).frame(width: size*0.26, height: size*0.26).offset(y: size*0.18)
            Capsule().fill(color).frame(width: size*0.1, height: size*0.1).offset(y: -size*0.46)
            Capsule().fill(color).frame(width: size*0.08, height: size*0.1).offset(x: size*0.34, y: -size*0.3).rotationEffect(.degrees(45))
            Capsule().fill(color).frame(width: lw*0.9, height: size*0.28).offset(y: -size*0.08)
            Circle().fill(color).frame(width: size*0.1, height: size*0.1)
        }
    }

    private var trophy: some View {
        let w = size, h = size
        return ZStack {
            // 손잡이.
            Path { p in
                p.move(to: CGPoint(x: w*0.31, y: h*0.20))
                p.addCurve(to: CGPoint(x: w*0.33, y: h*0.33),
                           control1: CGPoint(x: w*0.18, y: h*0.21), control2: CGPoint(x: w*0.19, y: h*0.33))
            }.stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: w*0.69, y: h*0.20))
                p.addCurve(to: CGPoint(x: w*0.67, y: h*0.33),
                           control1: CGPoint(x: w*0.82, y: h*0.21), control2: CGPoint(x: w*0.81, y: h*0.33))
            }.stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            // 컵.
            Path { p in
                p.move(to: CGPoint(x: w*0.30, y: h*0.16))
                p.addLine(to: CGPoint(x: w*0.70, y: h*0.16))
                p.addLine(to: CGPoint(x: w*0.62, y: h*0.34))
                p.addQuadCurve(to: CGPoint(x: w*0.50, y: h*0.50), control: CGPoint(x: w*0.60, y: h*0.48))
                p.addQuadCurve(to: CGPoint(x: w*0.38, y: h*0.34), control: CGPoint(x: w*0.40, y: h*0.48))
                p.closeSubpath()
            }.fill(color)
            // 기둥 + 2단 받침 (절대 위치).
            Rectangle().fill(color).frame(width: lw*1.2, height: h*0.10).position(x: w*0.5, y: h*0.56)
            Capsule().fill(color).frame(width: w*0.24, height: lw*1.3).position(x: w*0.5, y: h*0.64)
            Capsule().fill(color).frame(width: w*0.42, height: lw*1.5).position(x: w*0.5, y: h*0.72)
        }
        .frame(width: w, height: h)
    }

    private var medal: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size*0.4, y: size*0.06)); p.addLine(to: CGPoint(x: size*0.5, y: size*0.34))
                p.move(to: CGPoint(x: size*0.6, y: size*0.06)); p.addLine(to: CGPoint(x: size*0.5, y: size*0.34))
            }.stroke(color, style: stroke)
            CogShape(teeth: 10, innerRatio: 0.86).fill(color).frame(width: size*0.5, height: size*0.5).offset(y: size*0.18)
            Circle().fill(AppColors.paper1).frame(width: size*0.18, height: size*0.18).offset(y: size*0.18)
        }
    }

    private var openBook: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size*0.5, y: size*0.26))
                p.addQuadCurve(to: CGPoint(x: size*0.12, y: size*0.28), control: CGPoint(x: size*0.3, y: size*0.18))
                p.addLine(to: CGPoint(x: size*0.12, y: size*0.72))
                p.addQuadCurve(to: CGPoint(x: size*0.5, y: size*0.7), control: CGPoint(x: size*0.3, y: size*0.62))
                p.addQuadCurve(to: CGPoint(x: size*0.88, y: size*0.72), control: CGPoint(x: size*0.7, y: size*0.62))
                p.addLine(to: CGPoint(x: size*0.88, y: size*0.28))
                p.addQuadCurve(to: CGPoint(x: size*0.5, y: size*0.26), control: CGPoint(x: size*0.7, y: size*0.18))
            }.stroke(color, style: stroke)
            Capsule().fill(color).frame(width: lw*0.8, height: size*0.42).offset(y: size*0.01)
        }
    }

    private var pocketWatch: some View {
        ZStack {
            ring(0.74).offset(y: size*0.08)
            // 보우(고리)
            Circle().stroke(color, style: stroke).frame(width: size*0.18, height: size*0.18).offset(y: -size*0.38)
            Capsule().fill(color).frame(width: size*0.12, height: size*0.1).offset(y: -size*0.27)
            // 핸즈
            Capsule().fill(color).frame(width: lw*0.7, height: size*0.2).offset(y: size*0.02).rotationEffect(.degrees(40))
        }
    }

    private var column: some View {
        ZStack {
            Capsule().fill(color).frame(width: size*0.62, height: lw*1.2).offset(y: -size*0.34)
            Capsule().fill(color).frame(width: size*0.7, height: lw*1.2).offset(y: size*0.36)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(color).frame(width: lw*1.3, height: size*0.56)
                    .offset(x: CGFloat(i-1)*size*0.22)
            }
        }
    }

    private var movement: some View {
        ZStack {
            ring(0.9)
            CogShape(teeth: 8, innerRatio: 0.6).fill(color).frame(width: size*0.34, height: size*0.34).offset(x: -size*0.14, y: -size*0.1)
            CogShape(teeth: 7, innerRatio: 0.6).fill(color).frame(width: size*0.24, height: size*0.24).offset(x: size*0.18, y: size*0.14)
        }
    }

    private var hourglass: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size*0.26, y: size*0.16)); p.addLine(to: CGPoint(x: size*0.74, y: size*0.16))
                p.addLine(to: CGPoint(x: size*0.5, y: size*0.5)); p.addLine(to: CGPoint(x: size*0.74, y: size*0.84))
                p.addLine(to: CGPoint(x: size*0.26, y: size*0.84)); p.addLine(to: CGPoint(x: size*0.5, y: size*0.5))
                p.closeSubpath()
            }.stroke(color, style: stroke)
            Capsule().fill(color).frame(width: size*0.56, height: lw).offset(y: -size*0.34)
            Capsule().fill(color).frame(width: size*0.56, height: lw).offset(y: size*0.34)
        }
    }

    private var cycleArrows: some View {
        ZStack {
            Circle().trim(from: 0.05, to: 0.45).stroke(color, style: stroke).frame(width: size*0.7, height: size*0.7)
            Circle().trim(from: 0.55, to: 0.95).stroke(color, style: stroke).frame(width: size*0.7, height: size*0.7)
            Triangle().fill(color).frame(width: size*0.16, height: size*0.16).offset(x: size*0.34, y: -size*0.06).rotationEffect(.degrees(150))
            Triangle().fill(color).frame(width: size*0.16, height: size*0.16).offset(x: -size*0.34, y: size*0.06).rotationEffect(.degrees(-30))
        }
    }

    private var gem: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size*0.5, y: size*0.12))
                p.addLine(to: CGPoint(x: size*0.84, y: size*0.4))
                p.addLine(to: CGPoint(x: size*0.5, y: size*0.88))
                p.addLine(to: CGPoint(x: size*0.16, y: size*0.4))
                p.closeSubpath()
            }.stroke(color, style: stroke)
            Path { p in
                p.move(to: CGPoint(x: size*0.16, y: size*0.4)); p.addLine(to: CGPoint(x: size*0.84, y: size*0.4))
                p.move(to: CGPoint(x: size*0.34, y: size*0.4)); p.addLine(to: CGPoint(x: size*0.5, y: size*0.88))
                p.move(to: CGPoint(x: size*0.66, y: size*0.4)); p.addLine(to: CGPoint(x: size*0.5, y: size*0.88))
            }.stroke(color, style: StrokeStyle(lineWidth: lw*0.7, lineCap: .round))
        }
    }

    private var thumbsUp: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size*0.04).fill(color).frame(width: size*0.18, height: size*0.34).offset(x: -size*0.28, y: size*0.16)
            Path { p in
                p.move(to: CGPoint(x: size*0.34, y: size*0.9))
                p.addLine(to: CGPoint(x: size*0.34, y: size*0.46))
                p.addLine(to: CGPoint(x: size*0.5, y: size*0.16))
                p.addQuadCurve(to: CGPoint(x: size*0.6, y: size*0.18), control: CGPoint(x: size*0.58, y: size*0.1))
                p.addLine(to: CGPoint(x: size*0.56, y: size*0.42))
                p.addLine(to: CGPoint(x: size*0.82, y: size*0.42))
                p.addQuadCurve(to: CGPoint(x: size*0.8, y: size*0.62), control: CGPoint(x: size*0.86, y: size*0.52))
                p.addQuadCurve(to: CGPoint(x: size*0.7, y: size*0.9), control: CGPoint(x: size*0.78, y: size*0.84))
                p.closeSubpath()
            }.fill(color)
        }
    }

    private var camera: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size*0.1).stroke(color, style: stroke).frame(width: size*0.82, height: size*0.6)
            Capsule().fill(color).frame(width: size*0.22, height: size*0.1).offset(x: -size*0.18, y: -size*0.34)
            Circle().stroke(color, style: stroke).frame(width: size*0.28, height: size*0.28).offset(y: size*0.02)
        }
    }

    private var megaphone: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size*0.2, y: size*0.4)); p.addLine(to: CGPoint(x: size*0.5, y: size*0.4))
                p.addLine(to: CGPoint(x: size*0.78, y: size*0.2)); p.addLine(to: CGPoint(x: size*0.78, y: size*0.8))
                p.addLine(to: CGPoint(x: size*0.5, y: size*0.6)); p.addLine(to: CGPoint(x: size*0.2, y: size*0.6))
                p.closeSubpath()
            }.stroke(color, style: stroke)
            Path { p in
                p.move(to: CGPoint(x: size*0.34, y: size*0.6)); p.addLine(to: CGPoint(x: size*0.38, y: size*0.82))
            }.stroke(color, style: stroke)
        }
    }
}

// MARK: - Shapes

struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width*0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Wave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: 0, y: h*0.5))
        p.addCurve(to: CGPoint(x: w*0.5, y: h*0.5),
                   control1: CGPoint(x: w*0.16, y: 0), control2: CGPoint(x: w*0.34, y: h))
        p.addCurve(to: CGPoint(x: w, y: h*0.5),
                   control1: CGPoint(x: w*0.66, y: 0), control2: CGPoint(x: w*0.84, y: h))
        return p
    }
}

struct Crescent: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.addArc(center: CGPoint(x: c.x - r*0.5, y: c.y), radius: r*0.92,
                 startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        p.closeSubpath()
        // 좌우 반전 — 달이 반대 방향(왼쪽 볼록, 오른쪽 열림)을 향하도록.
        return p.applying(CGAffineTransform(scaleX: -1, y: 1))
                .applying(CGAffineTransform(translationX: rect.width, y: 0))
    }
}

struct StarShape: Shape {
    var points: Int = 5
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rO = min(rect.width, rect.height) / 2
        let rI = rO * 0.42
        let total = points * 2
        for i in 0..<total {
            let r = i.isMultiple(of: 2) ? rO : rI
            let a = Double(i) / Double(total) * 2 * .pi - .pi/2
            let pt = CGPoint(x: c.x + CGFloat(cos(a))*r, y: c.y + CGFloat(sin(a))*r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct Heart: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w*0.5, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h*0.3),
                   control1: CGPoint(x: w*0.1, y: h*0.7), control2: CGPoint(x: 0, y: h*0.5))
        p.addArc(center: CGPoint(x: w*0.25, y: h*0.3), radius: w*0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: w*0.75, y: h*0.3), radius: w*0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: w*0.5, y: h),
                   control1: CGPoint(x: w, y: h*0.5), control2: CGPoint(x: w*0.9, y: h*0.7))
        p.closeSubpath()
        return p
    }
}

struct Flame: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w*0.5, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h*0.65),
                   control1: CGPoint(x: w*0.9, y: h*0.3), control2: CGPoint(x: w, y: h*0.45))
        p.addArc(center: CGPoint(x: w*0.5, y: h*0.65), radius: w*0.5,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: w*0.5, y: 0),
                   control1: CGPoint(x: 0, y: h*0.45), control2: CGPoint(x: w*0.1, y: h*0.3))
        p.closeSubpath()
        return p
    }
}

struct Leaf: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w*0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w*0.5, y: h), control: CGPoint(x: w, y: h*0.4))
        p.addQuadCurve(to: CGPoint(x: w*0.5, y: 0), control: CGPoint(x: 0, y: h*0.4))
        p.closeSubpath()
        return p
    }
}

struct CrownPeaks: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h*0.2))
        p.addLine(to: CGPoint(x: w*0.25, y: h*0.6))
        p.addLine(to: CGPoint(x: w*0.5, y: 0))
        p.addLine(to: CGPoint(x: w*0.75, y: h*0.6))
        p.addLine(to: CGPoint(x: w, y: h*0.2))
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }
}

#Preview("Badge glyphs") {
    let ids = ["b10","b17","b18","b8","b19","b7","b1","b6","b24","b4","b16","b13","b14","b15","b21","b5","b9","b2","b22","b3","b11","b25","b20","b32","b23","b26","b27","b28","b29","b30","b31","b12","b33","b34","b35","b36","b37","b38"]
    return ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 18) {
            ForEach(ids, id: \.self) { id in
                VStack(spacing: 4) {
                    BadgeGlyph(id: id, size: 38, color: AppColors.accent)
                    Text(id).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }.padding()
    }
}
