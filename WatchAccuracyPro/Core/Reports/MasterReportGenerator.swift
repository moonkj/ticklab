import PDFKit
import SwiftUI
import UIKit

/// Sprint 6 (P2-7): 컬렉션 마스터 리포트 PDF — 전체 시계 포트폴리오.
/// ConditionReportGenerator 기반 확장.
/// 용도: 보험 증빙 / 도난 신고 / 딜러 포트폴리오.
@MainActor
enum MasterReportGenerator {
    private static let pageWidth: CGFloat  = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat     = 48

    static func generate(watches: [Watch], includePrices: Bool = true) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )
        return renderer.pdfData { ctx in
            // 커버 페이지
            ctx.beginPage()
            drawCover(watches: watches, includePrices: includePrices)

            // 시계별 1페이지씩
            for (index, watch) in watches.enumerated() {
                ctx.beginPage()
                drawWatchPage(watch: watch, index: index + 1, total: watches.count, includePrices: includePrices)
            }
        }
    }

    // MARK: - Cover

    private static func drawCover(watches: [Watch], includePrices: Bool) {
        var y: CGFloat = margin

        // 타이틀
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        NSAttributedString(string: String(localized: "report.collection.title"), attributes: titleAttrs)
            .draw(at: CGPoint(x: margin, y: y))
        y += 44

        // 생성 날짜
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.systemGray
        ]
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
        NSAttributedString(string: String(format: String(localized: "report.cover.subtitle"), dateStr, watches.count), attributes: subAttrs)
            .draw(at: CGPoint(x: margin, y: y))
        y += 24

        // 구분선
        drawDivider(y: y)
        y += 32

        // 시계 목록 테이블
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.systemIndigo
        ]
        NSAttributedString(string: String(localized: "report.col.brand"), attributes: headerAttrs).draw(at: CGPoint(x: margin, y: y))
        NSAttributedString(string: String(localized: "report.col.model"), attributes: headerAttrs).draw(at: CGPoint(x: margin + 120, y: y))
        NSAttributedString(string: String(localized: "report.col.movement"), attributes: headerAttrs).draw(at: CGPoint(x: margin + 300, y: y))
        if includePrices {
            NSAttributedString(string: String(localized: "report.col.purchasePrice"), attributes: headerAttrs).draw(at: CGPoint(x: margin + 420, y: y))
        }
        y += 18

        drawDivider(y: y)
        y += 12

        let rowAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.label
        ]
        let subRowAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.systemGray
        ]

        for watch in watches {
            NSAttributedString(string: watch.brand, attributes: rowAttrs).draw(at: CGPoint(x: margin, y: y))
            NSAttributedString(string: watch.model, attributes: rowAttrs).draw(at: CGPoint(x: margin + 120, y: y))
            NSAttributedString(string: watch.movementType.displayName, attributes: subRowAttrs).draw(at: CGPoint(x: margin + 300, y: y))
            if includePrices, let price = watch.purchasePrice {
                let fmt = NumberFormatter()
                fmt.numberStyle = .currency
                fmt.currencyCode = watch.purchaseCurrency ?? "KRW"
                fmt.maximumFractionDigits = 0
                let priceStr = fmt.string(from: NSDecimalNumber(decimal: price)) ?? ""
                NSAttributedString(string: priceStr, attributes: subRowAttrs).draw(at: CGPoint(x: margin + 420, y: y))
            }
            y += 16
            if y > pageHeight - margin { break } // 페이지 초과 방지
        }

        // 총 가치
        if includePrices {
            let total = watches.compactMap(\.purchasePrice).reduce(Decimal(0), +)
            if total > 0 {
                y += 8
                drawDivider(y: y)
                y += 16
                let totalFmt = NumberFormatter()
                totalFmt.numberStyle = .currency
                totalFmt.currencyCode = "KRW"
                totalFmt.maximumFractionDigits = 0
                let totalAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: UIColor.label
                ]
                NSAttributedString(string: String(format: String(localized: "report.cover.totalValue"), totalFmt.string(from: NSDecimalNumber(decimal: total)) ?? ""), attributes: totalAttrs)
                    .draw(at: CGPoint(x: margin + 300, y: y))
            }
        }

        drawFooter()
    }

    // MARK: - Watch page

    private static func drawWatchPage(watch: Watch, index: Int, total: Int, includePrices: Bool) {
        var y: CGFloat = margin

        // 사진
        if let data = watch.photoData, let img = UIImage(data: data) {
            img.draw(in: CGRect(x: margin, y: y, width: 100, height: 100))
        }

        // 헤더
        let brandAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.systemGray]
        let modelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: UIColor.label]
        let subAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.systemGray2]

        NSAttributedString(string: "\(index)/\(total)  |  \(watch.brand.uppercased())", attributes: brandAttrs).draw(at: CGPoint(x: margin + 116, y: y + 4))
        NSAttributedString(string: watch.model, attributes: modelAttrs).draw(at: CGPoint(x: margin + 116, y: y + 20))
        if let nick = watch.nickname { NSAttributedString(string: "\"\(nick)\"", attributes: subAttrs).draw(at: CGPoint(x: margin + 116, y: y + 50)) }

        y += 110
        drawDivider(y: y)
        y += 24

        // 스펙
        y = drawKV(String(localized: "report.spec.caliber"), watch.caliber == Watch.manualCaliberTag ? nil : watch.caliber, y: y)
        y = drawKV(String(localized: "report.col.movement"), watch.movementType.displayName, y: y)
        y = drawKV(String(localized: "report.spec.reference"), watch.referenceNumber, y: y)
        if includePrices {
            if let price = watch.purchasePrice {
                let fmt = NumberFormatter(); fmt.numberStyle = .currency
                fmt.currencyCode = watch.purchaseCurrency ?? "KRW"; fmt.maximumFractionDigits = 0
                y = drawKV(String(localized: "report.col.purchasePrice"), fmt.string(from: NSDecimalNumber(decimal: price)), y: y)
            }
        }
        y = drawKV(String(localized: "report.spec.purchaseDate"), watch.purchaseDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) }, y: y)
        y = drawKV(String(localized: "report.spec.warrantyExpiry"), watch.warrantyExpirationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) }, y: y)
        y += 4
        drawDivider(y: y)
        y += 20

        // 최근 측정
        if let last = watch.measurements.max(by: { $0.timestamp < $1.timestamp }) {
            NSAttributedString(string: String(localized: "report.last_measurement"), attributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.systemIndigo
            ]).draw(at: CGPoint(x: margin, y: y))
            y += 16
            y = drawKV(String(localized: "report.kv.rate"), String(format: "%+.1f s/d", last.rateSecondsPerDay), y: y)
            y = drawKV(String(localized: "report.kv.beat_error"), String(format: "%.1f ms", last.beatErrorMs), y: y)
            y = drawKV(String(localized: "report.measurement.confidenceLabel"), "\(last.confidenceScore)", y: y)
        }

        drawFooter()
    }

    @discardableResult
    private static func drawKV(_ key: String, _ value: String?, y: CGFloat) -> CGFloat {
        guard let value, !value.isEmpty else { return y }
        let kAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.systemGray]
        let vAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: UIColor.label]
        NSAttributedString(string: key, attributes: kAttrs).draw(at: CGPoint(x: margin, y: y))
        NSAttributedString(string: value, attributes: vAttrs).draw(at: CGPoint(x: margin + 120, y: y))
        return y + 15
    }

    private static func drawDivider(y: CGFloat) {
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setStrokeColor(UIColor.separator.cgColor); ctx?.setLineWidth(0.5)
        ctx?.move(to: CGPoint(x: margin, y: y + 6))
        ctx?.addLine(to: CGPoint(x: pageWidth - margin, y: y + 6))
        ctx?.strokePath()
    }

    private static func drawFooter() {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.systemGray3]
        NSAttributedString(string: String(localized: "report.footer.masterDisclaimer"), attributes: attrs)
            .draw(in: CGRect(x: margin, y: pageHeight - 36, width: pageWidth - margin * 2, height: 24))
    }
}
