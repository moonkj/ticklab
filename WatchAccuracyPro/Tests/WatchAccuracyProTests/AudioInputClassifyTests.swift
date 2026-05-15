import AVFoundation
import XCTest
@testable import WatchAccuracyPro

final class AudioInputClassifyTests: XCTestCase {
    func test_bluetooth_ports_map_to_bluetooth_type() {
        XCTAssertEqual(AudioInputManager.classify(portType: .bluetoothHFP), .bluetooth)
        XCTAssertEqual(AudioInputManager.classify(portType: .bluetoothA2DP), .bluetooth)
        XCTAssertEqual(AudioInputManager.classify(portType: .bluetoothLE), .bluetooth)
    }

    func test_wired_ports_map_to_wired_type() {
        XCTAssertEqual(AudioInputManager.classify(portType: .headsetMic), .wired)
        XCTAssertEqual(AudioInputManager.classify(portType: .lineIn), .wired)
    }

    func test_usb_audio_maps_to_external_type() {
        XCTAssertEqual(AudioInputManager.classify(portType: .usbAudio), .external)
    }

    func test_builtin_mic_maps_to_builtin_type() {
        XCTAssertEqual(AudioInputManager.classify(portType: .builtInMic), .builtin)
    }

    func test_unknown_port_falls_back_to_external() {
        XCTAssertEqual(AudioInputManager.classify(portType: .carAudio), .external)
        XCTAssertEqual(AudioInputManager.classify(portType: .HDMI), .external)
    }
}
