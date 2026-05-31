import SwiftData
import SwiftUI

/// #18 Watch별 통합 "생애 타임라인" — 한 시계의 첫만남·측정·착용·저널·정비를 한 시간축에.
/// R6 수렴: 신규 화면 남발 대신 이미 연결된 데이터를 내러티브로 꿰는 "그릇". 의존성 0.
/// 측정은 여러 노드 유형 중 하나일 뿐 — 생활기록 플랫폼의 핵심 표면.
struct WatchTimelineView: View {
    let watch: Watch
    @Query(sort: \JournalEntry.timestamp, order: .reverse) private var allJournal: [JournalEntry]
    @Query(sort: \WearLog.date, order: .reverse) private var allWear: [WearLog]

    private enum Kind {
        case meeting, measurement, wear, journal, service
        var icon: String {
            switch self {
            case .meeting:     return "sparkles"
            case .measurement: return "waveform.path.ecg"
            case .wear:        return "hand.wave"
            case .journal:     return "text.book.closed"
            case .service:     return "wrench.and.screwdriver"
            }
        }
        var color: Color {
            switch self {
            case .meeting:     return AppColors.accentDark
            case .measurement: return AppColors.info
            case .wear:        return AppColors.success
            case .journal:     return AppColors.ink2
            case .service:     return AppColors.warning
            }
        }
        var labelKey: String {
            switch self {
            case .meeting:     return "timeline.first_meeting"
            case .measurement: return "timeline.measurement"
            case .wear:        return "timeline.wear"
            case .journal:     return "timeline.journal"
            case .service:     return "timeline.service"
            }
        }
    }

    private struct Event: Identifiable {
        let id = UUID()
        let date: Date
        let kind: Kind
        let title: String
        let subtitle: String?
        let isOrigin: Bool
    }

    private var events: [Event] {
        var out: [Event] = []

        // 측정 — 한 노드 유형. rate 값만 간결히.
        for m in watch.measurements {
            let sign = m.rateSecondsPerDay >= 0 ? "+" : ""
            let title = "\(sign)\(String(format: "%.1f", m.rateSecondsPerDay)) \(String(localized: "unit.seconds_per_day"))"
            out.append(Event(date: m.timestamp, kind: .measurement, title: title, subtitle: nil, isOrigin: false))
        }
        // 정비 — Watch.serviceHistory [Date].
        for d in watch.serviceHistory {
            out.append(Event(date: d, kind: .service,
                             title: String(localized: "timeline.service"), subtitle: nil, isOrigin: false))
        }
        // 저널 (이 시계).
        for j in allJournal where j.watch?.id == watch.id {
            let snippet = j.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = snippet.isEmpty ? j.mood.localizedName : String(snippet.prefix(60))
            out.append(Event(date: j.timestamp, kind: .journal,
                             title: "\(j.mood.emoji) \(title)", subtitle: j.locationLabel, isOrigin: false))
        }
        // 착용 하이라이트 (이 시계, 하이라이트/태그 있는 것만 — 일반 착용은 노이즈).
        for w in allWear where w.watch?.id == watch.id && (w.isHighlight || !w.tags.isEmpty) {
            let tags = w.tags.joined(separator: " · ")
            let note = w.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = !note.isEmpty ? note : (tags.isEmpty ? String(localized: "timeline.wear") : tags)
            out.append(Event(date: w.date, kind: .wear, title: title,
                             subtitle: tags.isEmpty ? nil : tags, isOrigin: false))
        }

        var sorted = out.sorted { $0.date > $1.date }

        // 첫 만남 (origin) — 항상 맨 아래(가장 오래). 입력비용 0: 기존 필드 활용.
        let meetingDate = watch.purchaseDate ?? watch.createdAt
        let bits = [watch.receivedFrom, watch.purchaseLocation, watch.story]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        sorted.append(Event(date: meetingDate, kind: .meeting,
                            title: String(localized: "timeline.first_meeting"),
                            subtitle: bits.isEmpty ? nil : bits.joined(separator: " · "),
                            isOrigin: true))
        return sorted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, ev in
                    timelineRow(ev, isLast: idx == events.count - 1)
                }
            }
            .padding(20)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "timeline.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timelineRow(_ ev: Event, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(ev.kind.color.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: ev.kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ev.kind.color)
                }
                if !isLast {
                    Rectangle().fill(AppColors.rule)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(String(localized: String.LocalizationValue(ev.kind.labelKey)).uppercased())
                        .font(AppTypography.eyebrow)
                        .tracking(1.5)
                        .foregroundStyle(ev.kind.color)
                    Text(DateFormatter.localizedString(from: ev.date, dateStyle: .medium, timeStyle: .none))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                }
                Text(ev.title)
                    .font(ev.isOrigin ? AppTypography.headline : AppTypography.bodySmall)
                    .foregroundStyle(AppColors.ink0)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = ev.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 20)
            Spacer(minLength: 0)
        }
    }
}
