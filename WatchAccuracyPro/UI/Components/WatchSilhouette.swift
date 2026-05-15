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

    /// data.jsx 의 WatchSilhouette `a` (case) 색상.
    private var caseColor: Color {
        switch tone {
        case "silver": return Color(red: 0.79, green: 0.80, blue: 0.83)  // #C9CDD4
        case "blue":   return Color(red: 0.165, green: 0.290, blue: 0.498)  // #2A4A7F
        case "green":  return Color(red: 0.122, green: 0.310, blue: 0.227)  // #1F4F3A
        case "black":  return Color(red: 0.102, green: 0.106, blue: 0.180)  // #1A1B2E
        default:       return Color(red: 0.788, green: 0.663, blue: 0.380)  // #C9A961 gold
        }
    }

    /// 다이얼 색상 — jsx 의 `dialBg`.
    private var dialColor: Color {
        switch tone {
        case "silver": return Color(red: 0.910, green: 0.918, blue: 0.941)  // #E8EAF0
        case "blue":   return Color(red: 0.078, green: 0.169, blue: 0.325)  // #142B53
        case "green":  return Color(red: 0.059, green: 0.180, blue: 0.133)  // #0F2E22
        case "black":  return Color(red: 0.059, green: 0.067, blue: 0.094)  // #0F1118
        default:       return Color(red: 0.973, green: 0.910, blue: 0.722)  // #F8E8B8 gold dial
        }
    }

    /// 다이얼 위 글자/인디케이터 색 — silver 일 때만 dark, 나머지는 light.
    private var dialText: Color {
        tone == "silver"
            ? Color(red: 0.102, green: 0.106, blue: 0.180)   // #1A1B2E
            : Color(red: 0.980, green: 0.980, blue: 0.969)   // #FAFAF7
    }

    var body: some View {
        canvas
            .accessibilityElement()
            .accessibilityLabel(String(format: NSLocalizedString("a11y.watch_silhouette", comment: ""), model.capitalized))
    }

    private var canvas: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 60.0  // jsx viewBox 60×60 기준 scale.

            // 1. Lugs — top (y=2) + bottom (y=50) 각 2개.
            let lugColor = Color(red: 0.239, green: 0.247, blue: 0.431).opacity(0.55) // primary-700
            for (lx, ly) in [(22.0, 2.0), (32.0, 2.0), (22.0, 50.0), (32.0, 50.0)] {
                let rect = CGRect(x: lx * s, y: ly * s, width: 6 * s, height: 8 * s)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5 * s), with: .color(lugColor))
            }

            // 2. Crown — 우측 중앙.
            let crownRect = CGRect(x: 49 * s, y: 27 * s, width: 4 * s, height: 6 * s)
            ctx.fill(Path(roundedRect: crownRect, cornerRadius: 1 * s), with: .color(caseColor))

            // 3. Case — square (Tank/Reverso) or round.
            if isSquare {
                let rect = CGRect(x: 9 * s, y: 9 * s, width: 42 * s, height: 42 * s)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 5 * s), with: .color(caseColor))
            } else {
                let r = 21.0 * s
                let rect = CGRect(x: (30 - 21) * s, y: (30 - 21) * s, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(caseColor))
            }

            // 4. Bezel / dial.
            if isSquare {
                let rect = CGRect(x: 12 * s, y: 12 * s, width: 36 * s, height: 36 * s)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3 * s), with: .color(dialColor))
            } else {
                let r = 17.5 * s
                let rect = CGRect(x: (30 - 17.5) * s, y: (30 - 17.5) * s, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(dialColor))
            }

            // 5. 12 indices — radius 14.5 from center (30,30). i=0 (12시) r=1.6, 나머지 r=0.9.
            for i in 0..<12 {
                let angle = Double(i) * 30.0 - 90.0
                let radians = angle * .pi / 180
                let r = 14.5
                let cx = 30 + r * cos(radians)
                let cy = 30 + r * sin(radians)
                let ir = (i == 0 ? 1.6 : 0.9)
                let alpha = i % 3 == 0 ? 0.95 : 0.55
                let rect = CGRect(
                    x: (cx - ir) * s,
                    y: (cy - ir) * s,
                    width: 2 * ir * s,
                    height: 2 * ir * s
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(dialText.opacity(alpha)))
            }

            // 6. Hour hand — vertical short up (30,30) → (30,20).
            var hourPath = Path()
            hourPath.move(to: CGPoint(x: 30 * s, y: 30 * s))
            hourPath.addLine(to: CGPoint(x: 30 * s, y: 20 * s))
            ctx.stroke(
                hourPath,
                with: .color(dialText),
                style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round)
            )

            // 7. Minute hand — diagonal down-right (30,30) → (37,34).
            var minPath = Path()
            minPath.move(to: CGPoint(x: 30 * s, y: 30 * s))
            minPath.addLine(to: CGPoint(x: 37 * s, y: 34 * s))
            ctx.stroke(
                minPath,
                with: .color(dialText),
                style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round)
            )

            // 8. Center pin.
            let pinRect = CGRect(
                x: (30 - 1.2) * s, y: (30 - 1.2) * s,
                width: 2.4 * s, height: 2.4 * s
            )
            ctx.fill(Path(ellipseIn: pinRect), with: .color(caseColor))

            // 9. Chronograph sub-dial (speedmaster only).
            if model == "speedmaster" {
                let subRect = CGRect(
                    x: (30 - 3.5) * s, y: (40 - 3.5) * s,
                    width: 7 * s, height: 7 * s
                )
                ctx.stroke(
                    Path(ellipseIn: subRect),
                    with: .color(dialText.opacity(0.7)),
                    lineWidth: 0.5 * s
                )
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
        .init(brand: "Casio",   modelName: "G-Shock",      model: "sub",         tone: "black",  caliber: ""),
        .init(brand: "Citizen", modelName: "Eco-Drive",    model: "datejust",    tone: "silver", caliber: ""),
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
        .init(brand: "Chanel",   modelName: "J12",            model: "datejust", tone: "black",  caliber: "ETA_2824"),
        .init(brand: "Piaget",   modelName: "Polo",           model: "datejust", tone: "gold",   caliber: "ETA_2824"),
        .init(brand: "Longines", modelName: "Master",         model: "datejust", tone: "silver", caliber: "ETA_2824"),
    ]
}
