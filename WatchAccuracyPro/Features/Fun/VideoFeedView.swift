import SwiftUI

/// 큐레이션 YouTube 영상 피드 — 운영자가 등록한 채널의 신규 영상(언어별).
/// 재생은 YouTube 앱/사파리로 열기(약관: 스트림 추출·광고 우회 금지). BrandNewsView 패턴.
struct VideoFeedView: View {
    @StateObject private var service = YouTubeFeedService.shared
    @Environment(\.openURL) private var openURL
    /// nil = 전체, 값 = 해당 채널만.
    @State private var selectedChannel: String?
    @State private var showSuggest = false

    /// 피드에 등장하는 채널(중복 제거, 가나다/알파벳 정렬).
    private var distinctChannels: [String] {
        Array(Set(service.videos.map(\.channelTitle))).sorted()
    }

    /// 선택 채널 필터(선택이 현재 목록에 없으면 전체).
    private var displayedVideos: [YouTubeFeedService.YouTubeVideo] {
        guard let sel = selectedChannel, distinctChannels.contains(sel) else { return service.videos }
        return service.videos.filter { $0.channelTitle == sel }
    }

    var body: some View {
        Group {
            if service.isLoading && service.videos.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 220)
            } else if service.videos.isEmpty {
                EmptyState(
                    icon: "play.rectangle",
                    title: String(localized: "video.empty.title"),
                    message: String(localized: "video.empty.body")
                )
            } else {
                ScrollView {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // 채널이 2개 이상일 때만 — 전체 / 채널 선택.
                    if distinctChannels.count >= 2 {
                        Button { selectedChannel = nil } label: {
                            if selectedChannel == nil {
                                Label(String(localized: "video.filter.all"), systemImage: "checkmark")
                            } else { Text(String(localized: "video.filter.all")) }
                        }
                        ForEach(distinctChannels, id: \.self) { ch in
                            Button { selectedChannel = ch } label: {
                                if selectedChannel == ch { Label(ch, systemImage: "checkmark") } else { Text(ch) }
                            }
                        }
                        Divider()
                    }
                    // 항상 하단에 — 채널 제안.
                    Button { showSuggest = true } label: {
                        Label(String(localized: "video.suggest.menu"), systemImage: "paperplane")
                    }
                } label: {
                    if distinctChannels.count >= 2 {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(selectedChannel ?? String(localized: "video.filter.all")).lineLimit(1)
                        }
                        .font(.system(size: 14, weight: .semibold))
                    } else {
                        Image(systemName: "ellipsis.circle").font(.system(size: 17))
                    }
                }
            }
        }
        .sheet(isPresented: $showSuggest) { ChannelSuggestSheet() }
        .task { await service.load() }
        .refreshable { await service.load(force: true) }
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
                            AsyncImage(url: video.thumbnailHigh) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                case .failure:
                                    AsyncImage(url: video.thumbnailMid) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: { Color.clear }
                                default: Color.clear
                                }
                            }
                        }
                        .clipped()
                    HStack(spacing: 4) {
                        Image(systemName: "play.rectangle.fill")
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
