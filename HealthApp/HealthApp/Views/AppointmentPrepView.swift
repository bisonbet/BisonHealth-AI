import SwiftUI

// MARK: - Appointment Prep View
/// Primary tab: lists saved appointment-prep reports and starts new ones.
struct AppointmentPrepView: View {
    @StateObject private var manager = AppointmentPrepManager.shared
    @State private var showingNewPrep = false
    @State private var selectedPrep: AppointmentPrep?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        PlatformCapabilities.usesExpandedLayout(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        NavigationStack {
            Group {
                if manager.isLoading && manager.preps.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if manager.preps.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Appointment Prep")
            .navigationBarTitleDisplayMode(.inline)
            .dynamicType(.body, isIPad: isIPad)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticFeedbackManager.shared.impact()
                        showingNewPrep = true
                    } label: {
                        Image(systemName: "plus")
                            .touchTarget()
                    }
                    .voiceOverLabel(
                        "New Appointment Prep",
                        hint: "Start preparing for a doctor appointment",
                        traits: [.button]
                    )
                    .accessibilityIdentifier("prep.new")
                }
            }
            .navigationDestination(item: $selectedPrep) { prep in
                AppointmentPrepDetailView(prep: prep, manager: manager)
            }
        }
        .sheet(isPresented: $showingNewPrep) {
            AppointmentPrepEditorView(manager: manager)
        }
        .task {
            await manager.loadPreps()
        }
        .refreshable {
            await manager.loadPreps()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Prep for Your Appointment", systemImage: "stethoscope")
        } description: {
            Text("Turn your symptoms and health record into an organized timeline, questions for your doctor, and helpful background.")
        } actions: {
            Button {
                HapticFeedbackManager.shared.impact()
                showingNewPrep = true
            } label: {
                Text("New Appointment Prep")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(BisonTheme.gold)
        }
    }

    // MARK: - List

    private var listContent: some View {
        List {
            ForEach(manager.preps) { prep in
                Button {
                    HapticFeedbackManager.shared.selection()
                    selectedPrep = prep
                } label: {
                    PrepRow(prep: prep)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { try? await manager.delete(prep) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Prep Row
private struct PrepRow: View {
    let prep: AppointmentPrep

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.title3)
                .foregroundStyle(BisonTheme.gold)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(prep.resolvedTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let date = prep.appointmentDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Text("Updated \(prep.lastModified.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            StatusBadge(status: prep.status)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
