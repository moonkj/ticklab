import SwiftData
import SwiftUI

struct ServiceLogComposerView: View {
    let watch: Watch
    var existing: ServiceLog?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var type: ServiceType = .checkup
    @State private var date: Date = .init()
    @State private var center: String = ""
    @State private var costText: String = ""
    @State private var note: String = ""
    @State private var showingDiscardAlert = false

    private var isDirty: Bool {
        !center.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !costText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "service.section.type")) {
                    Picker(String(localized: "service.picker.type"), selection: $type) {
                        ForEach(ServiceType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(t)
                        }
                    }
                }
                Section(String(localized: "service.section.record")) {
                    DatePicker(String(localized: "service.date"), selection: $date, displayedComponents: .date)
                    TextField(String(localized: "service.center"), text: $center)
                    TextField(String(localized: "service.cost"), text: $costText)
                        .keyboardType(.numberPad)
                }
                Section(String(localized: "service.section.note")) {
                    TextField(String(localized: "service.note.placeholder"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String(localized: existing == nil ? "service.title.add" : "service.title.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        if isDirty { showingDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) { save() }.fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
            .alert(String(localized: "common.discard.title"), isPresented: $showingDiscardAlert) {
                Button(String(localized: "common.discard.confirm"), role: .destructive) { dismiss() }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "common.discard.message"))
            }
        }
    }

    private func loadExisting() {
        guard let existing else { return }
        type = existing.type
        date = existing.timestamp
        center = existing.serviceCenter
        if let cost = existing.costAmount {
            costText = "\(NSDecimalNumber(decimal: cost).intValue)"
        }
        note = existing.notes
    }

    private func save() {
        let log = existing ?? ServiceLog(watch: watch)
        log.type = type
        log.timestamp = date
        log.serviceCenter = center
        log.notes = note
        if let cost = Decimal(string: costText) {
            log.costAmount = cost
            log.costCurrency = "KRW"
        }
        // 다음 service 권장 일자 자동 계산.
        if let months = type.recommendedIntervalMonths {
            log.nextServiceDate = Calendar.current.date(byAdding: .month, value: months, to: date)
        }
        if existing == nil { modelContext.insert(log) }
        try? modelContext.save()
        dismiss()
    }
}
