import SwiftData
import SwiftUI
import UIKit

/// 시계 보관함 (Watchbox) — 디자인 SSOT screens-watchbox.jsx port.
/// 3/6/12 슬롯 × 4 마감재 (walnut/ebony/leather/linen) — pillow shape 받침대 + 시계 silhouette + brass nameplate.
struct WatchBoxView: View {
    @Query(sort: \Watch.id) private var watches: [Watch]
    @State private var slotCount: Int = 6
    @State private var material: Material = .walnut
    @State private var editing: Bool = false
    @Environment(\.dismiss) private var dismiss

    enum Material: String, CaseIterable, Identifiable {
        case walnut, ebony, leather, linen
        var id: String { rawValue }
        var label: String {
            switch self {
            case .walnut: return "WALNUT"
            case .ebony: return "EBONY"
            case .leather: return "LEATHER"
            case .linen: return "LINEN"
            }
        }
        /// 외함 색상.
        var outerColors: [Color] {
            switch self {
            case .walnut:  return [Color(red: 0.36, green: 0.23, blue: 0.12),
                                    Color(red: 0.55, green: 0.35, blue: 0.17),
                                    Color(red: 0.29, green: 0.17, blue: 0.09)]
            case .ebony:   return [Color(red: 0.102, green: 0.106, blue: 0.180),
                                    Color(red: 0.165, green: 0.133, blue: 0.200),
                                    Color(red: 0.059, green: 0.059, blue: 0.102)]
            case .leather: return [Color(red: 0.227, green: 0.122, blue: 0.071),
                                    Color(red: 0.361, green: 0.180, blue: 0.102),
                                    Color(red: 0.165, green: 0.071, blue: 0.031)]
            case .linen:   return [Color(red: 0.910, green: 0.863, blue: 0.753),
                                    Color(red: 0.949, green: 0.922, blue: 0.851),
                                    Color(red: 0.788, green: 0.725, blue: 0.549)]
            }
        }
        /// pillow (받침대) 색상.
        var pillowColors: (top: Color, bottom: Color) {
            switch self {
            case .walnut:  return (Color(red: 0.165, green: 0.129, blue: 0.102), Color(red: 0.059, green: 0.039, blue: 0.024))
            case .ebony:   return (Color(red: 0.122, green: 0.137, blue: 0.188), Color(red: 0.031, green: 0.039, blue: 0.063))
            case .leather: return (Color(red: 0.231, green: 0.141, blue: 0.094), Color(red: 0.078, green: 0.039, blue: 0.020))
            case .linen:   return (Color(red: 0.545, green: 0.498, blue: 0.361), Color(red: 0.290, green: 0.255, blue: 0.192))
            }
        }
        var fgColor: Color {
            switch self {
            case .walnut, .leather: return Color(red: 0.949, green: 0.902, blue: 0.800)
            case .ebony: return Color(red: 0.788, green: 0.663, blue: 0.380)  // gold
            case .linen: return Color(red: 0.290, green: 0.263, blue: 0.216)
            }
        }
    }

    private var slots: [Watch?] {
        Array(repeating: nil as Watch?, count: slotCount)
            .enumerated()
            .map { idx, _ in idx < watches.count ? watches[idx] : nil }
    }

    private var cols: Int { slotCount == 3 ? 1 : slotCount == 6 ? 2 : 3 }

    private var occupied: Int { slots.filter { $0 != nil }.count }
    private var brands: Int { Set(slots.compactMap { $0?.brand }).count }
    private var avgRate: Double? {
        let rates = watches.flatMap { w in w.measurements.map { $0.rateSecondsPerDay } }
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0, +) / Double(rates.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pickers
                    box
                    statsRow
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "menu.watchbox"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? String(localized: "common.done") : String(localized: "common.edit")) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation { editing.toggle() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(editing ? AppColors.accentDark : AppColors.primary500)
                }
            }
        }
    }

    private var pickers: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "watchbox.slots"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.ink2)
                HStack(spacing: 6) {
                    ForEach([3, 6, 12], id: \.self) { n in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeOut(duration: 0.2)) { slotCount = n }
                        } label: {
                            Text("\(n)구")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(slotCount == n ? AppColors.primaryDeep : AppColors.paper2)
                                .foregroundStyle(slotCount == n ? .white : AppColors.ink0)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "watchbox.material"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.ink2)
                HStack(spacing: 8) {
                    ForEach(Material.allCases) { m in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeOut(duration: 0.25)) { material = m }
                        } label: {
                            ZStack {
                                LinearGradient(
                                    colors: m.outerColors,
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                VStack {
                                    Spacer()
                                    Text(m.label)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .tracking(1.5)
                                        .foregroundStyle(m.fgColor)
                                        .padding(.bottom, 4)
                                }
                            }
                            .frame(height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(material == m ? AppColors.accent : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var box: some View {
        ZStack {
            // Outer case.
            LinearGradient(
                colors: material.outerColors,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // Hinges (top edge).
            VStack {
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Spacer()
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .overlay(Circle().fill(Color.white.opacity(0.1)).frame(width: 2, height: 2).offset(y: -1.5))
                        Spacer()
                    }
                }
                .padding(.top, 4)
                Spacer()
            }
            // Brand plaque (top-right brass).
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Text("TickLab")
                            .font(.system(size: 10, weight: .black, design: .serif))
                            .foregroundStyle(AppColors.primaryDeep)
                        Rectangle()
                            .fill(AppColors.primaryDeep.opacity(0.4))
                            .frame(width: 1, height: 9)
                        Text("EST.2026")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(AppColors.primaryDeep)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.831, green: 0.702, blue: 0.424),
                                     Color(red: 0.627, green: 0.533, blue: 0.259)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                }
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)
            // Tray + slot grid.
            VStack(spacing: 0) {
                Spacer()
                tray
                    .padding(.horizontal, 14)
                    .padding(.top, 32)
                    .padding(.bottom, 14)
            }
        }
        .frame(minHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 30)
    }

    private var tray: some View {
        ZStack {
            // Inner tray darker radial.
            RadialGradient(
                colors: [material.pillowColors.top.opacity(0.6), material.pillowColors.bottom],
                center: .init(x: 0.5, y: 0.4),
                startRadius: 0, endRadius: 280
            )
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: cols),
                spacing: 12
            ) {
                ForEach(Array(slots.enumerated()), id: \.offset) { idx, watch in
                    pillowSlot(idx: idx, watch: watch)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func pillowSlot(idx: Int, watch: Watch?) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if watch == nil {
                // Round 134: 빈 슬롯 tap → WatchBox 닫고 AddWatchView 진입 hint.
                // 사용자에게 안내 — direct 진입은 NavigationStack 충돌 위험.
            }
        } label: {
            ZStack {
                // Pillow radial — Round 138: 3구일 때 슬롯 가운데를 밝게 해서 구분 명확.
                RadialGradient(
                    colors: [
                        material.pillowColors.top.opacity(cols == 1 ? 1.2 : 1.0),
                        material.pillowColors.bottom
                    ],
                    center: .init(x: 0.5, y: 0.38),
                    startRadius: 0, endRadius: cols == 1 ? 200 : 80
                )
                .overlay(
                    // Round 138 사용자 보고: 3구일 때 슬롯 구분 안 보임 → stroke 강화 + 밝은 inner ring 추가.
                    RoundedRectangle(cornerRadius: cols == 3 ? 60 : 40)
                        .strokeBorder(.white.opacity(cols == 1 ? 0.22 : 0.08), lineWidth: cols == 1 ? 2 : 1)
                )
                .overlay(
                    // 슬롯 안쪽 highlight ring — gold 톤 (브랜드 통일).
                    RoundedRectangle(cornerRadius: cols == 3 ? 56 : 36)
                        .strokeBorder(material.fgColor.opacity(cols == 1 ? 0.15 : 0.0), lineWidth: 0.5)
                        .padding(6)
                )
                if let watch {
                    // Round 134 사용자 요청 (재조정):
                    //   3구(cols=1) — 슬롯 매우 큼 → 사진 180pt 로 크게
                    //   6구(cols=2) — 슬롯 중간 → 사진 110pt
                    //   12구(cols=3) — 슬롯 작음, 원 안에 맞춰야 → 사진 72pt 로 줄임
                    let photoSize: CGFloat = {
                        switch cols {
                        case 1: return 180
                        case 2: return 110
                        default: return 72  // cols == 3
                        }
                    }()
                    let nameplateMaxWidth: CGFloat = cols == 1 ? 180 : (cols == 2 ? 110 : 80)
                    let brandFont: CGFloat = cols == 1 ? 11 : (cols == 2 ? 9 : 7)
                    let modelFont: CGFloat = cols == 1 ? 9 : (cols == 2 ? 7.5 : 6)
                    VStack(spacing: cols == 1 ? 10 : 6) {
                        // Round 145 (Sora #1): NSCache 통한 UIImage 재사용 — 12 슬롯 매 body decode 방지.
                        if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: photoSize, height: photoSize)
                                .clipShape(Circle())
                        } else {
                            WatchSilhouette(watch: watch, size: photoSize)
                        }
                        // Brass nameplate — brand + model 두 줄.
                        VStack(spacing: 1) {
                            Text(watch.brand.uppercased())
                                .font(.system(size: brandFont, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .lineLimit(1)
                            Text(watch.model)
                                .font(.system(size: modelFont, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(AppColors.primaryDeep)
                        .padding(.horizontal, cols == 1 ? 10 : 6)
                        .padding(.vertical, cols == 1 ? 4 : 2)
                        .frame(maxWidth: nameplateMaxWidth)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.831, green: 0.702, blue: 0.424),
                                         Color(red: 0.549, green: 0.455, blue: 0.204)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                } else {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .strokeBorder(material.fgColor.opacity(0.5),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                                .frame(width: 32, height: 32)
                            Image(systemName: "plus")
                                .font(.system(size: 14))
                                .foregroundStyle(material.fgColor.opacity(0.5))
                        }
                        Text("EMPTY · #\(String(format: "%02d", idx + 1))")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(material.fgColor.opacity(0.5))
                    }
                }
            }
            .aspectRatio(cols == 3 ? 1.0 / 1.1 : 1.0 / 1.15, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cols == 3 ? 60 : 40))
            .rotationEffect(.degrees(editing ? (idx % 2 == 0 ? -0.6 : 0.6) : 0))
            .animation(
                editing
                    ? .easeInOut(duration: 0.25).repeatForever(autoreverses: true).delay(Double(idx) * 0.07)
                    : .default,
                value: editing
            )
        }
        .buttonStyle(.plain)
    }

    private var statsRow: some View {
        // Round 134 사용자 요청: 1x4 HStack → 2x2 grid + 카드 너비 2배.
        // 너비가 두 배되면 "+13.2 s/d" 같은 값이 한 줄에 들어감.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            statCard(label: "OCCUPIED", value: "\(occupied)/\(slotCount)")
            statCard(label: "BRANDS", value: "\(brands)")
            if let avg = avgRate {
                statCard(label: "AVG RATE", value: String(format: "%@%.1f", avg >= 0 ? "+" : "", avg), unit: "s/d")
            } else {
                statCard(label: "AVG RATE", value: "—")
            }
            statCard(label: "EMPTY", value: "\(slotCount - occupied)")
        }
    }

    private func statCard(label: String, value: String, unit: String? = nil) -> some View {
        // Round 134: 카드 내부 padding + 값 폰트 키움 (한 줄 안에 들어가게).
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(AppColors.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
