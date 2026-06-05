import SwiftData
import SwiftUI

/// Sprint 4 (P3-3): 컬렉션 하이라이트 타임라인.
/// 이벤트 태그 있거나 isHighlight 인 WearLog 를 시간 역순으로 표시.
/// Stats 탭 또는 분석 화면에서 진입.
struct HighlightTimelineView: View {
    @Query(sort: \WearLog.date, order: .reverse) private var allLogs: [WearLog]

    private var highlights: [WearLog] {
        allLogs.filter { $0.isHighlight || !$0.tags.isEmpty }
    }

    var body: some View {
        Group {
            if highlights.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(highlights) { log in
                        timelineRow(log)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "highlight.title"))
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.paper0.ignoresSafeArea())
    }

    private func timelineRow(_ log: WearLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 타임라인 라인 + 점
            VStack(spacing: 0) {
                Circle()
                    .fill(log.isHighlight ? AppColors.accent : AppColors.ink3)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                Rectangle()
                    .fill(AppColors.rule)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(DateFormatter.localizedString(from: log.date, dateStyle: .medium, timeStyle: .none))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                    if log.isHighlight {
                        ConceptGlyph(systemName: "star.fill", size: 12)
                            .foregroundStyle(AppColors.accent)
                    }
                }
                if let watch = log.watch {
                    Text("\(watch.brand) \(watch.model)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                }
                if !log.note.isEmpty {
                    Text(log.note)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.ink2)
                }
                if !log.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(log.tags, id: \.self) { tag in
                                Text(WearTag.displayName(for: tag))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppColors.accentDark)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(AppColors.accent50)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var emptyState: some View {
        EmptyState(
            icon: "star",
            title: String(localized: "highlight.empty.title"),
            message: String(localized: "highlight.empty.body")
        )
    }
}
