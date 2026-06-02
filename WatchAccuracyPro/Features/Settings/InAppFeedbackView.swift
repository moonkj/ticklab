import SwiftUI
import UIKit

/// Sprint 6 (P3-14): 인앱 피드백 시트.
/// 흔들기(Motion) 또는 설정 > 피드백 진입.
/// Round 175: Supabase(app_feedback)로 전송 → 운영 대시보드에서 확인 (구 mailto 대체).
struct InAppFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText: String = ""
    @State private var feedbackType: FeedbackType = .general
    @State private var isSubmitting: Bool = false
    @State private var submitSucceeded: Bool = false
    @State private var submitFailed: Bool = false

    enum FeedbackType: String, CaseIterable, Identifiable {
        case bug, suggestion, general
        var id: String { rawValue }
        var label: LocalizedStringResource {
            switch self {
            case .bug:        return "feedback.type.bug"
            case .suggestion: return "feedback.type.suggestion"
            case .general:    return "feedback.type.general"
            }
        }
        var icon: String {
            switch self {
            case .bug:        return "ant"
            case .suggestion: return "lightbulb"
            case .general:    return "bubble.left"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "feedback.section.type")) {
                    Picker(String(localized: "feedback.type.label"), selection: $feedbackType) {
                        ForEach(FeedbackType.allCases) { type in
                            Label(String(localized: type.label), systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(String(localized: "feedback.section.message")) {
                    TextField(String(localized: "feedback.placeholder"), text: $feedbackText, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .navigationTitle(String(localized: "feedback.nav.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "feedback.send")) {
                        submit()
                    }
                    .fontWeight(.semibold)
                    .disabled(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
            .alert(String(localized: "feedback.submit.success"), isPresented: $submitSucceeded) {
                Button(String(localized: "common.ok")) { dismiss() }
            }
            .alert(String(localized: "feedback.submit.failure"), isPresented: $submitFailed) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    /// Round 175: mailto 대신 Supabase(app_feedback)로 전송 → 운영 대시보드에서 확인.
    private func submit() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        Task {
            let ok = await CommunityService.shared.submitFeedback(
                type: feedbackType.rawValue, message: trimmed, appVersion: version)
            await MainActor.run {
                isSubmitting = false
                if ok { submitSucceeded = true } else { submitFailed = true }
            }
        }
    }
}
