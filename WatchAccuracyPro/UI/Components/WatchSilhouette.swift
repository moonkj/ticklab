import SwiftUI

/// 디자인 SSOT components.jsx WatchSilhouette — 60×60 viewBox SVG 정밀 port.
/// lugs (4) + crown + case (round/square) + bezel + 12 indices + 2 hands + center pin + chrono sub-dial.
struct WatchSilhouette: View {
    let model: String     // submariner / speedmaster / tank / reverso / gmt / datejust / sub
    let tone: String      // gold / silver / blue / green / black
    let size: CGFloat

    init(model: String = "submariner", tone: String = "gold", size: CGFloat = 60) {
        self.model = model
        self.tone = tone
        self.size = size
    }

    private var isSquare: Bool { model == "tank" || model == "reverso" }

    // MARK: - Tone palette (재설계: 금속 베젤 hi→lo + 다이얼 대비 마커 + 스트랩)
    /// 모든 톤이 광택 베젤 그라데이션을 갖고, marker(인덱스·핸드)는 다이얼과 항상 고대비.
    /// 핵심 수정: 기존엔 gold 다이얼(밝은 크림)에 밝은 마커를 써서 내부 대비가 없었음 → 어두운 마커로.
    private struct Palette {
        var caseHi: Color; var caseMid: Color; var caseLo: Color
        var dialInner: Color; var dialOuter: Color
        var marker: Color      // 인덱스/핸드 — 다이얼 대비 보장
        var strap: Color
        var seconds: Color     // 초침 강조색
    }

    private var palette: Palette {
        // 스틸 케이스(블루/그린/블랙/실버 공용) — 광택 그라데이션.
        let steelHi  = Color(red: 0.937, green: 0.945, blue: 0.957)
        let steelMid = Color(red: 0.760, green: 0.780, blue: 0.808)
        let steelLo  = Color(red: 0.522, green: 0.545, blue: 0.588)
        let leather  = Color(red: 0.196, green: 0.165, blue: 0.137)   // 다크 가죽 스트랩
        switch tone {
        case "silver":
            return Palette(caseHi: steelHi, caseMid: steelMid, caseLo: steelLo,
                           dialInner: Color(red: 0.968, green: 0.976, blue: 0.988),
                           dialOuter: Color(red: 0.862, green: 0.878, blue: 0.910),
                           marker: Color(red: 0.110, green: 0.118, blue: 0.196),
                           strap: steelMid, seconds: Color(red: 0.788, green: 0.180, blue: 0.196))
        case "blue":
            return Palette(caseHi: steelHi, caseMid: steelMid, caseLo: steelLo,
                           dialInner: Color(red: 0.156, green: 0.318, blue: 0.560),
                           dialOuter: Color(red: 0.063, green: 0.149, blue: 0.318),
                           marker: Color(red: 0.925, green: 0.945, blue: 0.984),
                           strap: leather, seconds: Color(red: 0.918, green: 0.659, blue: 0.353))
        case "green":
            return Palette(caseHi: steelHi, caseMid: steelMid, caseLo: steelLo,
                           dialInner: Color(red: 0.110, green: 0.357, blue: 0.267),
                           dialOuter: Color(red: 0.043, green: 0.176, blue: 0.129),
                           marker: Color(red: 0.910, green: 0.953, blue: 0.925),
                           strap: leather, seconds: Color(red: 0.847, green: 0.725, blue: 0.451))
        case "black":
            return Palette(caseHi: steelHi, caseMid: steelMid, caseLo: steelLo,
                           dialInner: Color(red: 0.149, green: 0.165, blue: 0.227),
                           dialOuter: Color(red: 0.055, green: 0.063, blue: 0.094),
                           marker: Color(red: 0.941, green: 0.945, blue: 0.961),
                           strap: leather, seconds: Color(red: 0.788, green: 0.180, blue: 0.196))
        default: // gold
            return Palette(caseHi: Color(red: 0.929, green: 0.851, blue: 0.647),
                           caseMid: Color(red: 0.788, green: 0.663, blue: 0.380),
                           caseLo: Color(red: 0.514, green: 0.396, blue: 0.176),
                           dialInner: Color(red: 0.988, green: 0.961, blue: 0.882),
                           dialOuter: Color(red: 0.933, green: 0.867, blue: 0.682),
                           marker: Color(red: 0.247, green: 0.184, blue: 0.063),
                           strap: Color(red: 0.290, green: 0.196, blue: 0.118),
                           seconds: Color(red: 0.514, green: 0.396, blue: 0.176))
        }
    }

    var body: some View {
        canvas
            .accessibilityElement()
            .accessibilityLabel(String(format: NSLocalizedString("a11y.watch_silhouette", comment: ""), model.capitalized))
    }

    private var canvas: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 60.0  // viewBox 60×60 기준 scale.
            let p = palette
            let cx = 30.0, cy = 30.0
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            // 시계 위치(0..12) → 단위 방향 벡터(12시 = 위).
            func dir(_ clock: Double) -> (dx: Double, dy: Double) {
                let a = (-90.0 + clock * 30.0) * .pi / 180
                return (cos(a), sin(a))
            }

            // 0. 스트랩(케이스 뒤) — 위/아래, 금속/가죽 그라데이션. 화면 위아래로 자연스럽게 빠짐.
            let strapShade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [p.strap.opacity(0.55), p.strap, p.strap.opacity(0.55)]),
                startPoint: pt(30, 0), endPoint: pt(30, 60))
            ctx.fill(Path(roundedRect: CGRect(x: 23.2 * s, y: -2 * s, width: 13.6 * s, height: 18 * s),
                          cornerRadius: 3 * s), with: strapShade)
            ctx.fill(Path(roundedRect: CGRect(x: 23.2 * s, y: 44 * s, width: 13.6 * s, height: 18 * s),
                          cornerRadius: 3 * s), with: strapShade)

            // 1. Crown — 우측, 케이스가 살짝 덮도록 먼저.
            ctx.fill(Path(roundedRect: CGRect(x: 49.4 * s, y: 26.4 * s, width: 4.6 * s, height: 7.2 * s),
                          cornerRadius: 1.2 * s),
                     with: .linearGradient(Gradient(colors: [p.caseHi, p.caseLo]),
                                           startPoint: pt(49, 27), endPoint: pt(54, 33)))

            // 2. Case(베젤) — 광택 그라데이션 + 드롭섀도(밝/어두운 배경 모두에서 분리).
            let caseShade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [p.caseHi, p.caseMid, p.caseLo]),
                startPoint: pt(13, 11), endPoint: pt(47, 49))
            let casePath: Path
            let dialPath: Path
            if isSquare {
                casePath = Path(roundedRect: CGRect(x: 9 * s, y: 9 * s, width: 42 * s, height: 42 * s), cornerRadius: 6 * s)
                dialPath = Path(roundedRect: CGRect(x: 13.5 * s, y: 13.5 * s, width: 33 * s, height: 33 * s), cornerRadius: 4 * s)
            } else {
                let cr = 21.0 * s
                casePath = Path(ellipseIn: CGRect(x: (cx - 21) * s, y: (cy - 21) * s, width: 2 * cr, height: 2 * cr))
                let dr = 16.5 * s
                dialPath = Path(ellipseIn: CGRect(x: (cx - 16.5) * s, y: (cy - 16.5) * s, width: 2 * dr, height: 2 * dr))
            }
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 3.2 * s, x: 0, y: 1.4 * s))
                layer.fill(casePath, with: caseShade)
            }

            // 3. 베젤/다이얼 경계 — 얇은 어두운 분리 링.
            ctx.stroke(dialPath, with: .color(.black.opacity(0.22)), lineWidth: 1.1 * s)

            // 4. Dial — radial 그라데이션(중앙이 밝음).
            ctx.fill(dialPath, with: .radialGradient(
                Gradient(colors: [p.dialInner, p.dialOuter]),
                center: pt(cx, cy), startRadius: 0, endRadius: 17 * s))

            // 5. Rehaut — 다이얼 안쪽 얇은 링(깊이감, 원형만).
            if !isSquare {
                let reR = 15.6 * s
                ctx.stroke(Path(ellipseIn: CGRect(x: (cx - 15.6) * s, y: (cy - 15.6) * s, width: 2 * reR, height: 2 * reR)),
                           with: .color(p.marker.opacity(0.16)), lineWidth: 0.6 * s)
            }

            // 6. 인덱스 — 아플라이드 바톤. 12/3/6/9 는 길고 두껍게.
            for i in 0..<12 {
                let d = dir(Double(i))
                let isMajor = i % 3 == 0
                let outerR = 14.6, innerR = isMajor ? 11.8 : 12.8
                var idx = Path()
                idx.move(to: pt(cx + d.dx * innerR, cy + d.dy * innerR))
                idx.addLine(to: pt(cx + d.dx * outerR, cy + d.dy * outerR))
                ctx.stroke(idx, with: .color(p.marker.opacity(isMajor ? 0.95 : 0.68)),
                           style: StrokeStyle(lineWidth: (isMajor ? 1.6 : 0.9) * s, lineCap: .round))
            }

            // 7. 핸드 — 클래식 10:10. 다우핀(삼각) 필 + 짧은 테일.
            func hand(clock: Double, length: Double, halfWidth: Double, tail: Double) -> Path {
                let d = dir(clock)
                let perp = (x: -d.dy, y: d.dx)
                var path = Path()
                path.move(to: pt(cx + d.dx * length, cy + d.dy * length))                 // tip
                path.addLine(to: pt(cx + perp.x * halfWidth, cy + perp.y * halfWidth))     // base L
                path.addLine(to: pt(cx - d.dx * tail, cy - d.dy * tail))                   // tail
                path.addLine(to: pt(cx - perp.x * halfWidth, cy - perp.y * halfWidth))     // base R
                path.closeSubpath()
                return path
            }
            ctx.fill(hand(clock: 10.1667, length: 8.6,  halfWidth: 1.5,  tail: 2.4), with: .color(p.marker))  // 시침
            ctx.fill(hand(clock: 2.0,     length: 12.4, halfWidth: 1.15, tail: 2.6), with: .color(p.marker))  // 분침

            // 8. 초침 — 얇은 강조선(대각) + 카운터웨이트.
            let sd = dir(7.4)
            var sec = Path()
            sec.move(to: pt(cx - sd.dx * 4.5, cy - sd.dy * 4.5))
            sec.addLine(to: pt(cx + sd.dx * 14.0, cy + sd.dy * 14.0))
            ctx.stroke(sec, with: .color(p.seconds), style: StrokeStyle(lineWidth: 0.7 * s, lineCap: .round))

            // 9. 센터 캡 — 금속 작은 원.
            let capR = 1.5 * s
            ctx.fill(Path(ellipseIn: CGRect(x: pt(cx, cy).x - capR, y: pt(cx, cy).y - capR, width: 2 * capR, height: 2 * capR)),
                     with: .linearGradient(Gradient(colors: [p.caseHi, p.caseLo]), startPoint: pt(28, 28), endPoint: pt(32, 32)))

            // 10. 크로노 서브다이얼(speedmaster).
            if model == "speedmaster" {
                let subR = 3.6 * s
                ctx.stroke(Path(ellipseIn: CGRect(x: pt(cx, 40).x - subR, y: pt(cx, 40).y - subR, width: 2 * subR, height: 2 * subR)),
                           with: .color(p.marker.opacity(0.55)), lineWidth: 0.6 * s)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 사용자가 등록한 Watch 인스턴스에서 silhouette key 매핑.
extension Watch {
    var silhouetteModel: String {
        let m = model.lowercased()
        if m.contains("speed") || m.contains("chrono") { return "speedmaster" }
        if m.contains("sub") { return "submariner" }
        if m.contains("gmt") { return "gmt" }
        if m.contains("date") { return "datejust" }
        if m.contains("tank") { return "tank" }
        if m.contains("reverso") { return "reverso" }
        return "submariner"
    }
    var silhouetteTone: String {
        let b = brand.lowercased()
        if b.contains("rolex") { return "green" }
        if b.contains("omega") { return "silver" }
        if b.contains("tudor") { return "black" }
        if b.contains("cartier") { return "gold" }
        if b.contains("jaeger") || b.contains("jlc") { return "gold" }
        if b.contains("iwc") { return "silver" }
        if b.contains("patek") { return "blue" }
        if b.contains("audemars") || b == "ap" { return "silver" }
        if b.contains("seiko") || b == "gs" { return "silver" }
        return "gold"
    }
}

extension WatchSilhouette {
    init(watch: Watch, size: CGFloat = 60) {
        self.init(model: watch.silhouetteModel, tone: watch.silhouetteTone, size: size)
    }
}

/// Popular models seed — data.jsx POPULAR_MODELS SSOT 일치.
struct PopularWatchSeed: Identifiable {
    let id: UUID = UUID()
    let brand: String
    let modelName: String
    let model: String   // silhouette key
    let tone: String    // silhouette tone
    let caliber: String
    /// 구동 방식 — 등록 시 그대로 반영. 기본 automatic. (쿼츠/솔라/스마트워치가 automatic 로 잘못 등록되던 버그 대응)
    var movementType: WatchMovementType = .automatic
}

enum PopularWatches {
    /// Round 84 (사용자 + 박지영 C1·C2): 입문 브랜드(Casio/Seiko/Citizen/Swatch) 추가 + 약자 풀네임화.
    /// 12-grid 에서 18 개로 확장. 가로 스크롤 grid 형태 권장.
    static let all: [PopularWatchSeed] = [
        // 입문 — 박지영(첫 시계 Casio·Seiko 5) 페르소나가 본인 시계 찾도록.
        // Round 99 (QA Critical H3): Casio G-Shock / Citizen Eco-Drive 는 quartz — ETA_2824 오매핑 제거.
        // Swatch Sistem51 은 자동(mechanical) — Sellita_SW200 으로 교정.
        // caliber 를 nil 이 아닌 올바른 값 or Unknown 로 명시.
        .init(brand: "Seiko",   modelName: "5 Sports",     model: "sub",         tone: "black",  caliber: "Seiko_7S26"),
        .init(brand: "Casio",   modelName: "G-Shock",      model: "sub",         tone: "black",  caliber: "", movementType: .quartz),
        .init(brand: "Citizen", modelName: "Eco-Drive",    model: "datejust",    tone: "silver", caliber: "", movementType: .solar),
        .init(brand: "Swatch",  modelName: "Sistem51",     model: "datejust",    tone: "blue",   caliber: "Sellita_SW200"),
        .init(brand: "Hamilton", modelName: "Khaki Field", model: "datejust",    tone: "black",  caliber: "ETA_2824"),
        .init(brand: "Tissot",  modelName: "PRX",          model: "datejust",    tone: "blue",   caliber: "ETA_2824"),
        // 중급
        .init(brand: "Rolex",   modelName: "Submariner",   model: "submariner",  tone: "green",  caliber: "Rolex_3135"),
        .init(brand: "Omega",   modelName: "Speedmaster",  model: "speedmaster", tone: "silver", caliber: "Omega_1861"),
        .init(brand: "Rolex",   modelName: "GMT-Master",   model: "gmt",         tone: "blue",   caliber: "Rolex_3135"),
        .init(brand: "Rolex",   modelName: "Datejust",     model: "datejust",    tone: "silver", caliber: "Rolex_3135"),
        .init(brand: "Tudor",   modelName: "Black Bay",    model: "sub",         tone: "black",  caliber: "Tudor_MT5602"),
        .init(brand: "Omega",   modelName: "Seamaster",    model: "sub",         tone: "blue",   caliber: "Omega_8800"),
        // 하이엔드 — 약자 → 풀네임 (박지영 C2 fix).
        .init(brand: "Cartier", modelName: "Tank",         model: "tank",        tone: "gold",   caliber: "Cartier_1847MC"),
        .init(brand: "Jaeger-LeCoultre", modelName: "Reverso", model: "reverso", tone: "gold",   caliber: "ETA_2824"),
        .init(brand: "IWC",     modelName: "Portugieser",  model: "datejust",    tone: "silver", caliber: "ETA_7750"),
        .init(brand: "Patek Philippe", modelName: "Nautilus", model: "sub",      tone: "blue",   caliber: "Patek_215PS"),
        .init(brand: "Audemars Piguet", modelName: "Royal Oak", model: "sub",    tone: "silver", caliber: "ETA_2824"),
        .init(brand: "Grand Seiko", modelName: "Snowflake", model: "sub",        tone: "silver", caliber: "ETA_2824"),
        .init(brand: "Vacheron Constantin", modelName: "Overseas", model: "sub", tone: "blue",   caliber: "ETA_2824"),
        .init(brand: "A. Lange & Söhne", modelName: "Lange 1",   model: "datejust", tone: "silver", caliber: "ETA_2824"),
        .init(brand: "Panerai",  modelName: "Luminor",        model: "sub",     tone: "black",   caliber: "ETA_2824"),
        .init(brand: "Hublot",   modelName: "Big Bang",       model: "sub",     tone: "black",   caliber: "ETA_2824"),
        .init(brand: "Blancpain", modelName: "Fifty Fathoms", model: "submariner", tone: "blue", caliber: "ETA_2824"),
        .init(brand: "Breitling", modelName: "Navitimer",     model: "speedmaster", tone: "silver", caliber: "ETA_7750"),
        .init(brand: "TAG Heuer", modelName: "Carrera",       model: "speedmaster", tone: "silver", caliber: "ETA_7750"),
        .init(brand: "Hermès",   modelName: "H08",            model: "tank",    tone: "silver",  caliber: "ETA_2824"),
        .init(brand: "Chanel",   modelName: "J12",            model: "datejust", tone: "black",  caliber: "", movementType: .quartz),
        .init(brand: "Piaget",   modelName: "Polo",           model: "datejust", tone: "gold",   caliber: "ETA_2824"),
        .init(brand: "Longines", modelName: "Master",         model: "datejust", tone: "silver", caliber: "ETA_2824"),
        // 쿼츠 · 전자(디지털) · 솔라 · 스마트워치 — 기계식 외 타입도 등록 가능(측정은 기계식 전용, 나머지는 생활기록).
        .init(brand: "Casio",   modelName: "F-91W",          model: "datejust",    tone: "black",  caliber: "", movementType: .quartz),
        .init(brand: "Casio",   modelName: "Edifice",        model: "speedmaster", tone: "silver", caliber: "", movementType: .quartz),
        .init(brand: "Seiko",   modelName: "Prospex Solar",  model: "sub",         tone: "blue",   caliber: "", movementType: .solar),
        .init(brand: "Timex",   modelName: "Weekender",      model: "datejust",    tone: "black",  caliber: "", movementType: .quartz),
        .init(brand: "Bulova",  modelName: "Precisionist",   model: "speedmaster", tone: "silver", caliber: "", movementType: .quartz),
        .init(brand: "Apple",   modelName: "Apple Watch",    model: "tank",        tone: "black",  caliber: "", movementType: .smartwatch),
        .init(brand: "Samsung", modelName: "Galaxy Watch",   model: "sub",         tone: "black",  caliber: "", movementType: .smartwatch),
        .init(brand: "Garmin",  modelName: "Fenix",          model: "sub",         tone: "black",  caliber: "", movementType: .smartwatch),
    ]
}
