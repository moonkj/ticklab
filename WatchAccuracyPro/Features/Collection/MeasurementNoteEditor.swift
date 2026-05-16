import SwiftData
import SwiftUI

/// Round 29 (Doyoon): HistoryRow tap 으로 열림. 측정마다 짧은 메모(자세/케이스 상태/이상치 사유 등).
/// 페르소나 김재철(워치메이커) + 이재현(컬렉터) wish — 측정 컨텍스트를 lose 하지 않기 위해.
/// Round 22 (Hyemi): WatchDetailView 1805 줄 다이어트 — modal editor 를 별 파일로 분리.
struct MeasurementNoteEditor: View {
    @Bindable var measurement: WatchMeasurement
    /// 저장 후 호출. 호출자가 modelContext.save() 책임.
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    /// 한 측정에 대한 메모 길이 cap — 길어지면 export/공유 시 잘림.
    private let maxLength = 280

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                contextHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Divider().background(AppColors.rule)
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(String(localized: "measurement.note.placeholder"))
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.ink3)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                    TextEditor(text: $draft)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.ink0)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .focused($focused)
                        .onChange(of: draft) { _, new in
                            if new.count > maxLength {
                                draft = String(new.prefix(maxLength))
                            }
                        }
                }
                HStack {
                    Spacer()
                    Text("\(draft.count)/\(maxLength)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "measurement.note.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(AppColors.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        measurement.notes = trimmed.isEmpty ? nil : trimmed
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(AppColors.accent)
                    .fontWeight(.medium)
                }
            }
        }
        .onAppear {
            draft = measurement.notes ?? ""
        }
        .task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            focused = true
        }
    }

    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatTimestamp(measurement.timestamp))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatRate(measurement.rateSecondsPerDay))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.ink0)
                Text(String(localized: "unit.seconds_per_day"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
                Spacer()
                Chip("\(measurement.confidenceScore)",
                     tone: measurement.confidenceScore >= 80 ? .success
                        : measurement.confidenceScore >= 50 ? .warning : .danger,
                     small: true)
            }
        }
    }

    private func formatTimestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: d).uppercased()
    }

    private func formatRate(_ rate: Double) -> String {
        String(format: "%+.1f", rate)
    }
}
