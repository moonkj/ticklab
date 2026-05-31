import Foundation
import UIKit
import Vision

/// Sprint 7 (P3-6): 케이스백 사진 OCR — Vision VNRecognizeTextRequest.
/// 시리얼 번호, 브랜드명, 캘리버 등 각인 텍스트 자동 추출.
/// 완전 온디바이스 (Hard Rule #6 준수).
@MainActor
enum CasebackOCRService {

    struct OCRResult {
        let rawLines: [String]
        let serialCandidate: String?   // 시리얼 번호 후보 (숫자+영문 8~15자)
        let caliberCandidate: String?  // 캘리버 후보 (CAL./Cal. 뒤 문자열)
        let brandCandidate: String?    // 브랜드명 후보 (첫 줄 또는 알려진 브랜드)
    }

    private static let knownBrands: Set<String> = [
        "ROLEX", "OMEGA", "IWC", "PATEK", "AUDEMARS", "SEIKO", "GRAND SEIKO",
        "TUDOR", "CARTIER", "JAEGER", "BREITLING", "TAG HEUER", "LONGINES",
        "TISSOT", "HAMILTON", "PANERAI", "NOMOS", "ZENITH", "CITIZEN"
    ]

    static func recognizeText(from imageData: Data) async -> OCRResult? {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                guard error == nil,
                      let observations = req.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                continuation.resume(returning: parseLines(lines))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // 각인은 언어 교정 끄기
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private static func parseLines(_ lines: [String]) -> OCRResult {
        var serialCandidate: String?
        var caliberCandidate: String?
        var brandCandidate: String?

        for line in lines {
            let upper = line.uppercased().trimmingCharacters(in: .whitespaces)

            // 시리얼 번호: 숫자+영문 혼합 8~15자 (순수 숫자 포함)
            if serialCandidate == nil {
                let serialPattern = try? NSRegularExpression(pattern: #"[A-Z0-9]{8,15}"#)
                if let match = serialPattern?.firstMatch(
                    in: upper, range: NSRange(upper.startIndex..., in: upper)
                ), let range = Range(match.range, in: upper) {
                    let candidate = String(upper[range])
                    // 브랜드명이나 "AUTOMATIC" 같은 단어는 제외
                    if !knownBrands.contains(candidate) && candidate != "AUTOMATIC" && candidate != "STAINLESS" {
                        serialCandidate = String(line[Range(match.range, in: line)!])
                    }
                }
            }

            // 캘리버: "CAL.", "Cal.", "CALIBRE" 뒤에 오는 숫자/영문
            if caliberCandidate == nil {
                let calPattern = try? NSRegularExpression(pattern: #"(?:CAL\.|Cal\.|CALIBRE)\s*([A-Z0-9/]+)"#, options: .caseInsensitive)
                if let match = calPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   match.numberOfRanges > 1,
                   let r = Range(match.range(at: 1), in: line) {
                    caliberCandidate = String(line[r])
                }
            }

            // 브랜드: 알려진 브랜드명 포함 줄
            if brandCandidate == nil {
                for brand in knownBrands where upper.contains(brand) {
                    brandCandidate = brand.capitalized
                    break
                }
            }
        }

        return OCRResult(
            rawLines: lines,
            serialCandidate: serialCandidate,
            caliberCandidate: caliberCandidate,
            brandCandidate: brandCandidate
        )
    }
}
