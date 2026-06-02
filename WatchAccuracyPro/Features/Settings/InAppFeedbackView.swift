import SwiftUI
import UIKit

/// Sprint 6 (P3-14): 인앱 피드백 시트.
/// 흔들기(Motion) 또는 설정 > 피드백 진입.
/// 현재 화면 스크린샷 자동 첨부 → 이메일로 전송.
struct InAppFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText: String = ""
    @State private var feedbackType: FeedbackType = .general
    @State private var isSubmitting: Bool = false
    @State private var showingMail: Bool = false

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
                Section {
                    Text(String(localized: "feedback.email.hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.ink3)
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
        }
        .presentationDetents([.large])
    }

    private func submit() {
        guard !feedbackText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // 이메일 URL scheme으로 피드백 전송
        let subject = "[\(feedbackType.rawValue.uppercased())] \(String(localized: "feedback.email.subject"))"
        let body = feedbackText + "\n\n---\nApp Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailURL = URL(string: "mailto:imurmkj@naver.com?subject=\(encodedSubject)&body=\(encodedBody)")!
        if UIApplication.shared.canOpenURL(mailURL) {
            UIApplication.shared.open(mailURL)
        }
        dismiss()
    }
}
