import Foundation
import Network
import SwiftUI

/// Sprint 2 (P0-2.2): 네트워크 상태 실시간 모니터링.
/// `NWPathMonitor` 래핑 — Brand League / OTA 등 외부 호출 무음 실패 시 사용자에게 배너 표시.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// 현재 네트워크 도달 가능 여부.
    private(set) var isConnected: Bool = true
    /// 셀룰러/WiFi 구분 — 차후 데이터 절약 모드에 사용 가능.
    private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ticklab.network.monitor", qos: .utility)

    private init() {
        start()
    }

    private func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

/// Sprint 2 (P0-2.2): 오프라인 배너 — 화면 상단에 1줄로 표시.
/// RootTabView 또는 ScrollView 위에 attach 권장.
struct OfflineBanner: View {
    @State private var monitor = NetworkMonitor.shared

    var body: some View {
        if !monitor.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .semibold))
                Text(String(localized: "network.offline.banner"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(AppColors.warning)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
