import SwiftUI
import SwiftData

struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]
    @State private var showingAdd = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if watches.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(String(localized: "collection.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddWatchView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "stopwatch")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(AppColors.textMuted)
            Text(String(localized: "collection.empty.title"))
                .font(AppTypography.title)
            Text(String(localized: "collection.empty.subtitle"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            PrimaryButton(String(localized: "collection.empty.cta")) {
                showingAdd = true
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
    }

    private var list: some View {
        List {
            ForEach(watches) { watch in
                NavigationLink(value: watch) {
                    WatchRowView(watch: watch)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        watch.deleteCascade(in: modelContext)
                        try? modelContext.save()
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Watch.self) { watch in
            WatchDetailView(watch: watch)
        }
    }
}

#Preview {
    CollectionView()
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
        .environment(UserPreferences())
}
