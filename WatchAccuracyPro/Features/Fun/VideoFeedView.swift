import SwiftUI

/// 큐레이션 YouTube 영상 피드 — 운영자가 등록한 채널의 신규 영상(언어별).
/// 재생은 YouTube 앱/사파리로 열기(약관: 스트림 추출·광고 우회 금지). BrandNewsView 패턴.
struct VideoFeedView: View {
    @StateObject private var service = YouTubeFeedService.shared
    @Environment(\.openURL) private var openURL
    /// 비어있으면 전체, 값이 있으면 그 채널들만(복수 선택).
    @State private var selectedChannels: Set<String> = []
    @State private var showSuggest = false
    /// Round 173 (사용자 보고): 최초 로딩 동안 스피너가 확실히 뜨도록 — isLoading 타이밍과 무관하게 보장.
    @State private var didFirstLoad = false

    /// 피드에 등장하는 채널(중복 제거, 가나다/알파벳 정렬).
    private var distinctChannels: [String] {
        Array(Set(service.videos.map(\.channelTitle))).sorted()
    }

    /// 현재 목록에 실제로 있는 선택 채널만(새로고침으로 사라진 선택 무시).
    private var activeChannels: Set<String> {
        selectedChannels.intersection(Set(distinctChannels))
    }

    /// 선택 채널 필터(선택 없으면 전체).
    private var displayedVideos: [YouTubeFeedService.YouTubeVideo] {
        let active = activeChannels
        guard !active.isEmpty else { return service.videos }
        return service.videos.filter { active.contains($0.channelTitle) }
    }

    private func toggleChannel(_ ch: String) {
        if selectedChannels.contains(ch) { selectedChannels.remove(ch) } else { selectedChannels.insert(ch) }
    }

    var body: some View {
        Group {
            if (service.isLoading || !didFirstLoad) && service.videos.isEmpty {
                // 하이라이트 빈상태와 동일한 회전 링 스피너 — 로딩 완료 시 위 조건이 false 가 되어 즉시 콘텐츠 표시.
                AnimatedEmptyIcon(icon: "play.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .frame(maxHeight: .infinity)
            } else if service.videos.isEmpty {
                EmptyState(
                    icon: "play.rectangle",
                    title: String(localized: "video.empty.title"),
                    message: String(localized: "video.empty.body")
                )
            } else {
                // 자동 로터 pull-to-refresh — 당기면 로터가 돌고 새로고침.
                RotorRefreshScrollView(onRefresh: { await service.load(force: true) }) {
                    LazyVStack(spacing: 16) {
                        ForEach(displayedVideos) { video in
                            videoCard(video)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
        .navigationTitle(String(localized: "video.feed.title"))
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.paper0.ignoresSafeArea())
        // Round 173 (사용자 보고): 상단 nav 바를 본문(paper0)과 통일 — 흰색 띠/버튼 가시성 문제 해소.
        .toolbarBackground(AppColors.paper0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // 채널이 2개 이상일 때만 — 전체 / 채널 복수 선택.
                    // Toggle 사용: 체크 칼럼이 항상 고정폭이라 토글해도 메뉴 너비가 안 바뀜(상자 이동 방지).
                    if distinctChannels.count >= 2 {
                        Toggle(String(localized: "video.filter.all"), isOn: Binding(
                            get: { activeChannels.isEmpty },
                            set: { on in if on { selectedChannels.removeAll() } }))
                        ForEach(distinctChannels, id: \.self) { ch in
                            Toggle(ch, isOn: Binding(
                                get: { selectedChannels.contains(ch) },
                                set: { _ in toggleChannel(ch) }))
                        }
                        Divider()
                    }
                    // 항상 하단에 — 채널 제안.
                    Button { showSuggest = true } label: {
                        Label(String(localized: "video.suggest.menu"), systemImage: "paperplane")
                    }
                } label: {
                    // 고정폭 아이콘(텍스트 X) — 선택이 바뀌어도 버튼 너비 불변 → 메뉴 anchor 고정.
                    let filtered = distinctChannels.count >= 2 && !activeChannels.isEmpty
                    Image(systemName: distinctChannels.count < 2 ? "ellipsis.circle"
                          : (filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"))
                        .font(.system(size: 17))
                        .foregroundStyle(filtered ? AppColors.accent : AppColors.ink0)
                }
                .menuActionDismissBehavior(.disabled)   // 복수 선택 — 토글해도 메뉴 유지.
            }
        }
        .sheet(isPresented: $showSuggest) { ChannelSuggestSheet() }
        .task { await service.load(); didFirstLoad = true }
    }

    private func videoCard(_ video: YouTubeFeedService.YouTubeVideo) -> some View {
        Button {
            if let url = video.watchURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // 16:9 썸네일(maxres→실패 시 mq, 둘 다 16:9라 잘림 없음) + YouTube 어포던스.
                ZStack(alignment: .bottomTrailing) {
                    Color(AppColors.paper2)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            // 빠른 로딩: 작고 항상 존재하는 mqdefault 를 먼저 표시(즉시 보임) →
                            //   maxres 는 성공 시 위로 fade-in(화질 업그레이드). 이전엔 maxres 먼저라
                            //   maxres 없는 영상마다 404 대기 후 mqdefault → 전체 로딩이 매우 느렸음.
                            ZStack {
                                AsyncImage(url: video.thumbnailMid) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: { Color.clear }
                                AsyncImage(url: video.thumbnailHigh) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill().transition(.opacity)
                                    } else { Color.clear }
                                }
                            }
                        }
                        .clipped()
                    HStack(spacing: 4) {
                        ConceptGlyph(systemName: "play.rectangle.fill", size: 12)
                        Text(String(localized: "video.watch_on_youtube"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(video.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(video.channelTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.accentDark)
                        .lineLimit(1)
                    Text("·").foregroundStyle(AppColors.ink3)
                    Text(video.publishedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 채널 제안 — 사용자가 추천 YouTube 채널 주소를 운영자에게 제출.
private struct ChannelSuggestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var note = ""
    @State private var sending = false
    @State private var done = false

    private var canSend: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "video.suggest.url"), text: $url)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField(String(localized: "video.suggest.note"), text: $note, axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    Text(String(localized: "video.suggest.hint"))
                }
                Section {
                    Button {
                        sending = true
                        Task {
                            let ok = await CommunityService.shared.submitChannelSuggestion(
                                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                            sending = false
                            if ok { done = true }
                        }
                    } label: {
                        if sending { ProgressView() } else { Text(String(localized: "video.suggest.submit")) }
                    }
                    .disabled(!canSend)
                }
            }
            .navigationTitle(String(localized: "video.suggest.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .alert(String(localized: "video.suggest.done"), isPresented: $done) {
                Button(String(localized: "common.done")) { dismiss() }
            }
        }
    }
}
