import ImageIO
import UIKit
import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — EXIFStripper / WatchPhotoProcessor / PhotoQuality 의 순수 in-memory 경로.
/// 합성 UIImage 만 사용 (PhotosPicker/파일/네트워크/Vision 없음). 결정론적.
///
/// EXIFStripper.strippedJPEG / WatchPhotoProcessor.process 는 모두 nonisolated 정적 함수이므로
/// 클래스 @MainActor 어노테이션 불필요.
final class ImageHelperTests: XCTestCase {

    // MARK: - 합성 이미지 헬퍼

    /// 작은 단색 이미지를 만들어 JPEG Data 로 인코딩 — 디스크/카메라 없이 결정론적.
    private func makeJPEGData(width: CGFloat = 48, height: CGFloat = 32,
                             color: UIColor = .systemBlue) -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        // 0.9 압축 — strip 경로와 무관한 임의 입력 인코딩.
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            XCTFail("합성 JPEG 인코딩 실패")
            return Data()
        }
        return data
    }

    /// JPEG magic number (FF D8 FF) 검사 — 출력이 유효한 JPEG 인지 확인.
    private func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }

    // MARK: - EXIFStripper.strippedJPEG (watchMode=false 기본 경로)

    func test_strippedJPEG_returns_valid_jpeg() {
        let input = makeJPEGData()
        let out = EXIFStripper.strippedJPEG(from: input)
        let unwrapped = try? XCTUnwrap(out)
        XCTAssertNotNil(unwrapped, "유효 JPEG 입력은 nil 이 아니어야 한다")
        if let out { XCTAssertTrue(isJPEG(out), "출력은 유효한 JPEG 여야 한다") }
    }

    func test_strippedJPEG_invalid_data_returns_nil() {
        // UIImage(data:) 실패 → nil 반환 분기.
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        XCTAssertNil(EXIFStripper.strippedJPEG(from: garbage))
    }

    func test_strippedJPEG_empty_data_returns_nil() {
        XCTAssertNil(EXIFStripper.strippedJPEG(from: Data()))
    }

    func test_strippedJPEG_decodes_to_same_pixel_size() {
        // strip 후 재인코딩해도 픽셀 크기는 유지돼야 한다 (.up orientation 입력).
        let input = makeJPEGData(width: 64, height: 40)
        guard let out = EXIFStripper.strippedJPEG(from: input),
              let decoded = UIImage(data: out),
              let inDecoded = UIImage(data: input) else {
            XCTFail("strip 출력 디코드 실패")
            return
        }
        // strip 은 리사이즈 안 함 → 입력과 동일 픽셀 크기(렌더러 스케일 무관).
        XCTAssertEqual(decoded.size.width * decoded.scale, inDecoded.size.width * inDecoded.scale, accuracy: 1.0)
        XCTAssertEqual(decoded.size.height * decoded.scale, inDecoded.size.height * inDecoded.scale, accuracy: 1.0)
    }

    func test_strippedJPEG_removes_no_exif_in_synthetic_input() {
        // 합성 입력엔 GPS/EXIF 가 없지만, 출력에 GPS dictionary 가 없음을 확인 (회귀 가드).
        let input = makeJPEGData()
        guard let out = EXIFStripper.strippedJPEG(from: input),
              let src = CGImageSourceCreateWithData(out as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            XCTFail("출력 메타데이터 조회 실패")
            return
        }
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "strip 출력에 GPS 메타데이터가 없어야 한다")
    }

    // MARK: - EXIFStripper.strippedJPEG (watchMode=true → WatchPhotoProcessor 위임)

    func test_strippedJPEG_watchMode_standard_returns_valid_jpeg() {
        let input = makeJPEGData()
        let out = EXIFStripper.strippedJPEG(from: input, watchMode: true, style: .standard)
        let unwrapped = try? XCTUnwrap(out)
        XCTAssertNotNil(unwrapped)
        if let out { XCTAssertTrue(isJPEG(out)) }
    }

    func test_strippedJPEG_watchMode_invalid_data_returns_nil() {
        let garbage = Data([0x10, 0x20, 0x30])
        XCTAssertNil(EXIFStripper.strippedJPEG(from: garbage, watchMode: true, style: .standard))
    }

    // MARK: - WatchPhotoProcessor.process (모든 ProcessingStyle 분기)

    func test_process_standard_returns_valid_jpeg() {
        let input = makeJPEGData()
        let out = WatchPhotoProcessor.process(input, style: .standard)
        let unwrapped = try? XCTUnwrap(out)
        XCTAssertNotNil(unwrapped)
        if let out { XCTAssertTrue(isJPEG(out)) }
    }

    func test_process_caseback_returns_valid_jpeg() {
        // caseback 분기 — exposure/contrast/sharpen/toneCurve 필터 체인.
        let input = makeJPEGData(width: 80, height: 60, color: .darkGray)
        let out = WatchPhotoProcessor.process(input, style: .caseback)
        let unwrapped = try? XCTUnwrap(out)
        XCTAssertNotNil(unwrapped, "caseback 보정 출력은 nil 이 아니어야 한다")
        if let out { XCTAssertTrue(isJPEG(out)) }
    }

    func test_process_vivid_returns_valid_jpeg() {
        // vivid 분기 — vibrance/saturation 필터 체인.
        let input = makeJPEGData(width: 80, height: 60, color: .systemTeal)
        let out = WatchPhotoProcessor.process(input, style: .vivid)
        let unwrapped = try? XCTUnwrap(out)
        XCTAssertNotNil(unwrapped, "vivid 보정 출력은 nil 이 아니어야 한다")
        if let out { XCTAssertTrue(isJPEG(out)) }
    }

    func test_process_invalid_data_returns_nil() {
        // UIImage/cgImage 생성 실패 → nil 반환 가드.
        let garbage = Data([0xAA, 0xBB, 0xCC, 0xDD])
        XCTAssertNil(WatchPhotoProcessor.process(garbage, style: .standard))
        XCTAssertNil(WatchPhotoProcessor.process(garbage, style: .caseback))
        XCTAssertNil(WatchPhotoProcessor.process(garbage, style: .vivid))
    }

    func test_process_preserves_pixel_size() {
        // 보정은 픽셀 크기를 변경하지 않아야 한다 (filter 만 적용, resize 없음).
        let input = makeJPEGData(width: 50, height: 50)
        guard let out = WatchPhotoProcessor.process(input, style: .standard),
              let decoded = UIImage(data: out),
              let inDecoded = UIImage(data: input) else {
            XCTFail("process 출력 디코드 실패")
            return
        }
        // 보정은 filter 만 — 입력과 동일 픽셀 크기.
        XCTAssertEqual(decoded.size.width * decoded.scale, inDecoded.size.width * inDecoded.scale, accuracy: 2.0)
        XCTAssertEqual(decoded.size.height * decoded.scale, inDecoded.size.height * inDecoded.scale, accuracy: 2.0)
    }

    // MARK: - ProcessingStyle enum

    func test_processingStyle_all_cases_and_ids() {
        XCTAssertEqual(ProcessingStyle.allCases.count, 3)
        XCTAssertEqual(ProcessingStyle.standard.id, "standard")
        XCTAssertEqual(ProcessingStyle.caseback.id, "caseback")
        XCTAssertEqual(ProcessingStyle.vivid.id, "vivid")
        XCTAssertEqual(ProcessingStyle(rawValue: "vivid"), .vivid)
    }

    // MARK: - PhotoQuality enum

    func test_photoQuality_jpeg_values() {
        XCTAssertEqual(PhotoQuality.standard.jpegQuality, 0.85, accuracy: 1e-6)
        XCTAssertEqual(PhotoQuality.high.jpegQuality, 0.95, accuracy: 1e-6)
        XCTAssertEqual(PhotoQuality.original.jpegQuality, 1.0, accuracy: 1e-6)
    }

    func test_photoQuality_all_cases() {
        XCTAssertEqual(PhotoQuality.allCases.count, 3)
    }

    func test_photoQuality_current_defaults_to_standard_when_unset() {
        let key = "ticklab.photoQuality"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(PhotoQuality.current, .standard)
    }

    func test_photoQuality_current_reads_userdefaults() {
        let key = "ticklab.photoQuality"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(PhotoQuality.high.rawValue, forKey: key)
        XCTAssertEqual(PhotoQuality.current, .high)
        // 알 수 없는 값 → standard 폴백.
        UserDefaults.standard.set("nonsense", forKey: key)
        XCTAssertEqual(PhotoQuality.current, .standard)
    }
}
