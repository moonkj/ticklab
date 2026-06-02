import PDFKit
import SwiftUI
import UIKit

/// Sprint 3 (P2-6): 컨디션 리포트 PDF 온디바이스 생성.
/// PDFKit UIGraphicsPDFRenderer — 서버 불필요, 개인정보 외부 전송 없음.
/// 템플릿: 심플 스타일 (매거진 스타일은 Phase 2).
@MainActor
enum ConditionReportGenerator {
    private static let pageWidth: CGFloat  = 595   // A4 pt
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat     = 48

    static func generate(for watch: Watch, measurements: [WatchMeasurement]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin
            y = drawHeader(watch: watch, y: y)
            y = drawDivider(y: y)
            y = drawSpecSection(watch: watch, y: y)
            y = drawDivider(y: y)
            y = drawMeasurementSection(measurements: measurements, y: y)
            if let price = watch.purchasePrice, let priceStr = formattedPrice(watch: watch) {
                y = drawDivider(y: y)
                _ = drawFinanceSection(watch: watch, price: priceStr, wearCount: measurements.count, y: y)
            }
            drawFooter()
        }
    }

    // MARK: - Draw helpers

    @discardableResult
    private static func drawHeader(watch: Watch, y: CGFloat) -> CGFloat {
        var currentY = y

        // 시계 사진 (있으면)
        if let data = watch.photoData, let img = UIImage(data: data) {
            let size: CGFloat = 80
            img.draw(in: CGRect(x: margin, y: currentY, width: size, height: size))
        }

        // 브랜드 + 모델
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.systemGray
        ]
        let brand = NSAttributedString(string: watch.brand.uppercased(), attributes: brandAttrs)
        brand.draw(at: CGPoint(x: margin + 96, y: currentY + 4))

        let modelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        let model = NSAttributedString(string: watch.model, attributes: modelAttrs)
        model.draw(at: CGPoint(x: margin + 96, y: currentY + 22))

        // 날짜
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.systemGray2
        ]
        NSAttributedString(string: dateStr, attributes: dateAttrs)
            .draw(at: CGPoint(x: margin + 96, y: currentY + 52))

        // TickLab Pro 워터마크
        let wmAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.systemIndigo.withAlphaComponent(0.7)
        ]
        NSAttributedString(string: String(localized: "report.watermark.certified"), attributes: wmAttrs)
            .draw(at: CGPoint(x: pageWidth - margin - 80, y: currentY))

        currentY += 96
        return currentY
    }

    private static func drawDivider(y: CGFloat) -> CGFloat {
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setStrokeColor(UIColor.separator.cgColor)
        ctx?.setLineWidth(0.5)
        ctx?.move(to: CGPoint(x: margin, y: y + 8))
        ctx?.addLine(to: CGPoint(x: pageWidth - margin, y: y + 8))
        ctx?.strokePath()
        return y + 24
    }

    @discardableResult
    private static func drawSpecSection(watch: Watch, y: CGFloat) -> CGFloat {
        var currentY = y
        currentY = drawSectionTitle(String(localized: "report.section.spec"), y: currentY)
        let rows: [(String, String?)] = [
            (String(localized: "report.spec.reference"), watch.referenceNumber),
            (String(localized: "report.spec.caliber"), watch.caliber == Watch.manualCaliberTag ? nil : watch.caliber),
            (String(localized: "report.col.movement"), watch.movementType.displayName),
        ]
        for (k, v) in rows {
            if let v, !v.isEmpty {
                currentY = drawKeyValue(key: k, value: v, y: currentY)
            }
        }
        return currentY
    }

    @discardableResult
    private static func drawMeasurementSection(measurements: [WatchMeasurement], y: CGFloat) -> CGFloat {
        var currentY = y
        currentY = drawSectionTitle(String(format: String(localized: "report.section.measurementHistory"), min(measurements.count, 5)), y: currentY)
        let recent = measurements.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5)
        if recent.isEmpty {
            currentY = drawKeyValue(key: "", value: String(localized: "report.measurement.noRecords"), y: currentY)
        } else {
            for m in recent {
                let dateStr = DateFormatter.localizedString(from: m.timestamp, dateStyle: .short, timeStyle: .none)
                let rateStr = String(format: "%+.1f s/d", m.rateSecondsPerDay)
                let conf = String(format: String(localized: "report.measurement.confidenceValue"), m.confidenceScore)
                currentY = drawKeyValue(key: dateStr, value: "\(rateStr)  \(conf)", y: currentY)
            }
        }
        return currentY
    }

    @discardableResult
    private static func drawFinanceSection(watch: Watch, price: String, wearCount: Int, y: CGFloat) -> CGFloat {
        var currentY = y
        currentY = drawSectionTitle(String(localized: "report.section.finance"), y: currentY)
        currentY = drawKeyValue(key: String(localized: "report.col.purchasePrice"), value: price, y: currentY)
        if wearCount > 0, let p = watch.purchasePrice {
            let cpw = NSDecimalNumber(decimal: p / Decimal(wearCount))
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = watch.purchaseCurrency ?? "KRW"
            if let cpwStr = fmt.string(from: cpw) {
                currentY = drawKeyValue(key: String(format: String(localized: "report.finance.costPerWear"), wearCount), value: cpwStr, y: currentY)
            }
        }
        return currentY
    }

    private static func drawFooter() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.systemGray3
        ]
        NSAttributedString(
            string: String(localized: "report.footer.conditionDisclaimer"),
            attributes: attrs
        ).draw(in: CGRect(x: margin, y: pageHeight - 36, width: pageWidth - margin * 2, height: 24))
    }

    @discardableResult
    private static func drawSectionTitle(_ title: String, y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.systemIndigo
        ]
        NSAttributedString(string: title.uppercased(), attributes: attrs)
            .draw(at: CGPoint(x: margin, y: y))
        return y + 18
    }

    @discardableResult
    private static func drawKeyValue(key: String, value: String, y: CGFloat) -> CGFloat {
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.systemGray
        ]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.label
        ]
        if !key.isEmpty {
            NSAttributedString(string: key, attributes: keyAttrs)
                .draw(at: CGPoint(x: margin, y: y))
        }
        NSAttributedString(string: value, attributes: valAttrs)
            .draw(at: CGPoint(x: margin + 160, y: y))
        return y + 16
    }

    private static func formattedPrice(watch: Watch) -> String? {
        guard let price = watch.purchasePrice else { return nil }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = watch.purchaseCurrency ?? "KRW"
        return fmt.string(from: NSDecimalNumber(decimal: price))
    }
}
