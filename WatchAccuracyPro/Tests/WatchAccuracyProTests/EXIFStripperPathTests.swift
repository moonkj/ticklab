import UIKit
import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — EXIFStripper 의 파일 경로 / 저장·삭제 / watchMode 보정 분기.
///   · savePhoto → resolvePhotoPath → deletePhoto round-trip (파일명만 반환 규약)
///   · resolvePhotoPath: 파일명 / 존재하는 절대경로 / 없는 절대경로 분기
///   · strippedJPEG(watchMode:true) 의 caseback / vivid style 위임 분기
///
/// 기존 ImageHelperTests 는 strippedJPEG(watchMode:false), watchMode standard,
/// WatchPhotoProcessor.process(직접), PhotoQuality 만 다룬다 — 여기선 그 외 경로만 덮는다.
/// EXIFStripper 는 nonisolated enum 정적 함수 — 클래스 @MainActor 불필요.
final class EXIFStripperPathTests: XCTestCase {

    /// 작은 단색 JPEG Data — 디스크/카메라 없이 결정론적.
    private func makeJPEGData(width: CGFloat = 40, height: CGFloat = 30,
                             color: UIColor = .systemGreen) -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            XCTFail("합성 JPEG 인코딩 실패")
            return Data()
        }
        return data
    }

    private func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }

    // MARK: - savePhoto / resolvePhotoPath / deletePhoto round-trip

    func test_savePhoto_returns_filename_only_and_resolves() throws {
        let filename = try XCTUnwrap(EXIFStripper.savePhoto(makeJPEGData()),
                                     "유효 JPEG 는 파일명을 반환해야 한다")
        defer { EXIFStripper.deletePhoto(filename) }
        // 규약: 절대경로가 아닌 파일명만 반환 ("/" 미포함, .jpg 확장자).
        XCTAssertFalse(filename.contains("/"), "savePhoto 는 파일명만 반환해야 한다")
        XCTAssertTrue(filename.hasSuffix(".jpg"))
        // resolvePhotoPath 로 실제 디스크 경로 복원 + 파일 존재.
        let resolved = try XCTUnwrap(EXIFStripper.resolvePhotoPath(filename))
        XCTAssertTrue(resolved.contains("/photos/"), "photos 디렉토리 하위로 resolve")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved), "저장된 파일이 디스크에 있어야 한다")
    }

    func test_savePhoto_invalid_data_returns_nil() {
        // strippedJPEG nil (UIImage 디코드 실패) → savePhoto 도 nil.
        XCTAssertNil(EXIFStripper.savePhoto(Data([0x00, 0x01, 0x02])))
    }

    func test_deletePhoto_removes_file() throws {
        let filename = try XCTUnwrap(EXIFStripper.savePhoto(makeJPEGData()))
        let resolvedBefore = try XCTUnwrap(EXIFStripper.resolvePhotoPath(filename))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedBefore))

        EXIFStripper.deletePhoto(filename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolvedBefore),
                       "deletePhoto 후 파일이 삭제돼야 한다")
    }

    func test_deletePhoto_unknown_filename_is_noop() {
        // resolvePhotoPath 가 경로를 만들지만 파일은 없음 → removeItem 실패 무시, 크래시 없음.
        EXIFStripper.deletePhoto("\(UUID().uuidString).jpg")
    }

    // MARK: - resolvePhotoPath 분기

    func test_resolvePhotoPath_filename_builds_photos_dir_path() throws {
        // "/" 미포함 → photos 디렉토리 하위 경로 생성 (파일 존재 여부와 무관).
        let path = try XCTUnwrap(EXIFStripper.resolvePhotoPath("abc123.jpg"))
        XCTAssertTrue(path.hasSuffix("/photos/abc123.jpg"))
    }

    func test_resolvePhotoPath_existing_absolute_path_returned_asis() throws {
        // 레거시 절대경로 — 파일이 실제로 존재하면 그대로 반환.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        try makeJPEGData().write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = EXIFStripper.resolvePhotoPath(tmp.path)
        XCTAssertEqual(resolved, tmp.path, "존재하는 절대경로는 그대로 반환")
    }

    func test_resolvePhotoPath_missing_absolute_path_with_no_migration_returns_nil() {
        // 절대경로인데 원본도 없고 photos 디렉토리에 동명 파일도 없음 → nil.
        let bogus = "/var/does-not-exist/\(UUID().uuidString).jpg"
        XCTAssertNil(EXIFStripper.resolvePhotoPath(bogus))
    }

    func test_resolvePhotoPath_legacy_absolute_migrates_to_photos_dir() throws {
        // 레거시 절대경로 파일은 사라졌지만 동일 파일명이 photos 디렉토리에 존재 → 마이그레이션 resolve.
        let filename = try XCTUnwrap(EXIFStripper.savePhoto(makeJPEGData()))
        defer { EXIFStripper.deletePhoto(filename) }
        // 존재하지 않는 레거시 절대경로지만 lastPathComponent 는 저장된 파일명과 동일.
        let legacyAbsolute = "/legacy/container/path/\(filename)"
        let resolved = try XCTUnwrap(EXIFStripper.resolvePhotoPath(legacyAbsolute),
                                     "동명 파일이 photos 디렉토리에 있으면 마이그레이션 resolve")
        XCTAssertTrue(resolved.hasSuffix("/photos/\(filename)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    // MARK: - strippedJPEG(watchMode:true) caseback / vivid 위임

    func test_strippedJPEG_watchMode_caseback_returns_valid_jpeg() {
        let out = EXIFStripper.strippedJPEG(from: makeJPEGData(width: 60, height: 50, color: .darkGray),
                                            watchMode: true, style: .caseback)
        let unwrapped = try? XCTUnwrap(out)
        XCTAssertNotNil(unwrapped, "watchMode caseback 위임 출력은 nil 이 아니어야 한다")
        if let out { XCTAssertTrue(isJPEG(out)) }
    }

    func test_strippedJPEG_watchMode_vivid_returns_valid_jpeg() {
        let out = EXIFStripper.strippedJPEG(from: makeJPEGData(width: 60, height: 50, color: .systemTeal),
                                            watchMode: true, style: .vivid)
        let unwrapped = try? XCTUnwrap(out)
        XCTAssertNotNil(unwrapped, "watchMode vivid 위임 출력은 nil 이 아니어야 한다")
        if let out { XCTAssertTrue(isJPEG(out)) }
    }
}
