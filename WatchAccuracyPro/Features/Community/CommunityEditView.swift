import SwiftUI

/// 본인 커뮤니티 글 수정 — 캡션(내용) 편집. 사진·브랜드는 유지.
/// posts_update_own RLS(author_uid = auth.uid())로 서버에서 본인 글만 허용.
struct CommunityEditView: View {
    let post: Community.Post
    @Environment(\.dismiss) private var dismiss
    private let service = CommunityService.shared

    @State private var caption: String
    @State private var saving = false
    @State private var blocked = false
    @State private var blockMessage = ""

    init(post: Community.Post) {
        self.post = post
        _caption = State(initialValue: post.caption ?? "")
    }

    /// 글-전용(사진 없음) 글은 캡션이 비면 안 됨.
    private var isTextOnly: Bool { (post.imagePath ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "community.caption.placeholder"),
                              text: $caption, axis: .vertical)
                        .lineLimit(3...10)
                        .onChange(of: caption) { _, new in
                            if new.count > CommunityTextModerator.maxLength {
                                caption = String(new.prefix(CommunityTextModerator.maxLength))
                            }
                        }
                    Text("\(caption.count)/\(CommunityTextModerator.maxLength)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink3)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } footer: {
                    if !isTextOnly {
                        Text(String(localized: "community.edit.photo_kept"))
                    }
                }
            }
            .navigationTitle(String(localized: "community.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() }
                    else { Button(String(localized: "common.save")) { save() } }
                }
            }
            .alert(String(localized: "community.moderation.text.blocked.title"), isPresented: $blocked) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(blockMessage) }
        }
    }

    private func save() {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if isTextOnly && trimmed.isEmpty {
            blockMessage = String(localized: "community.compose.text_only.empty"); blocked = true; return
        }
        switch CommunityTextModerator.screen(trimmed) {
        case .allowed:
            break
        case .tradeBan:
            blockMessage = String(localized: "community.moderation.trade.blocked.body"); blocked = true; return
        case .profane, .tooLong:
            blockMessage = String(localized: "community.moderation.text.blocked.body"); blocked = true; return
        }
        saving = true
        Task {
            let ok = await service.updateMyPost(post, caption: trimmed)
            saving = false
            if ok { dismiss() }
            else { blockMessage = service.lastError ?? String(localized: "community.error.network"); blocked = true }
        }
    }
}
