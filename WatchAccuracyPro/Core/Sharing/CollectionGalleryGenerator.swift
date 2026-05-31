import Foundation

/// Sprint 10 (P2-16): 컬렉션 공개 갤러리 — 정적 HTML 생성.
/// 서버 없이 Files 앱 저장 or AirDrop/이메일로 공유.
/// 브라우저에서 바로 열 수 있는 self-contained HTML.
enum CollectionGalleryGenerator {

    static func generate(watches: [Watch], includePrices: Bool = false, ownerName: String = "") -> URL? {
        let html = buildHTML(watches: watches, includePrices: includePrices, ownerName: ownerName)
        guard let data = html.data(using: .utf8) else { return nil }

        let filename = "TickLab_Collection_\(DateFormatter().apply { $0.dateFormat = "yyyyMMdd" }.string(from: Date())).html"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }

    private static func buildHTML(watches: [Watch], includePrices: Bool, ownerName: String) -> String {
        let cards = watches.map { watchCard($0, includePrices: includePrices) }.joined(separator: "\n")
        let title = ownerName.isEmpty ? "TickLab Collection" : "\(ownerName)'s Collection"
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)

        return """
        <!DOCTYPE html>
        <html lang="ko">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(title)</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, sans-serif; background: #FAFAF7; color: #1A1B2E; padding: 24px 16px; }
          .header { text-align: center; margin-bottom: 32px; }
          .header h1 { font-size: 28px; font-weight: 700; }
          .header p { color: #888; font-size: 13px; margin-top: 6px; }
          .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; }
          .card { background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
          .card-img { width: 100%; height: 200px; object-fit: cover; background: #E8E8E4; display: flex; align-items: center; justify-content: center; font-size: 48px; }
          .card-body { padding: 16px; }
          .brand { font-size: 11px; font-weight: 600; letter-spacing: 2px; color: #888; text-transform: uppercase; }
          .model { font-size: 18px; font-weight: 600; margin-top: 4px; }
          .meta { font-size: 12px; color: #888; margin-top: 8px; }
          .price { font-size: 14px; font-weight: 700; color: #2A4B8C; margin-top: 8px; }
          .footer { text-align: center; margin-top: 40px; font-size: 11px; color: #CCC; }
          .footer a { color: #CCC; }
        </style>
        </head>
        <body>
        <div class="header">
          <h1>⌚ \(title)</h1>
          <p>\(watches.count)개 시계 · \(date)</p>
        </div>
        <div class="grid">
        \(cards)
        </div>
        <div class="footer">
          <p>⌚ Measured & tracked with <a href="\(ReferralService.shareURL.absoluteString)">TickLab</a></p>
          <p style="font-size:10px;color:#DDD;">iPhone 마이크로 시계 정확도를 측정하는 앱 · Watch accuracy on your iPhone</p>
        </div>
        </body>
        </html>
        """
    }

    private static func watchCard(_ watch: Watch, includePrices: Bool) -> String {
        let imageTag: String
        if let data = watch.photoData,
           let base64 = data.base64EncodedString().isEmpty ? nil : data.base64EncodedString() {
            imageTag = "<img class=\"card-img\" src=\"data:image/jpeg;base64,\(base64)\" alt=\"\(watch.model)\">"
        } else {
            imageTag = "<div class=\"card-img\">⌚</div>"
        }

        let priceHTML: String
        if includePrices, let price = watch.purchasePrice {
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = watch.purchaseCurrency ?? "KRW"
            fmt.maximumFractionDigits = 0
            let priceStr = fmt.string(from: NSDecimalNumber(decimal: price)) ?? ""
            priceHTML = "<div class=\"price\">\(priceStr)</div>"
        } else {
            priceHTML = ""
        }

        let movementInfo = watch.movementType.displayName
        let caliber = watch.caliber != nil && watch.caliber != Watch.manualCaliberTag
            ? " · \(watch.caliber!)" : ""

        return """
        <div class="card">
          \(imageTag)
          <div class="card-body">
            <div class="brand">\(watch.brand)</div>
            <div class="model">\(watch.model)</div>
            <div class="meta">\(movementInfo)\(caliber)</div>
            \(priceHTML)
          </div>
        </div>
        """
    }
}

private extension DateFormatter {
    func apply(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self); return self
    }
}
