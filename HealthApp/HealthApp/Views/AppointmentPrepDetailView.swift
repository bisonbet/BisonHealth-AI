import SwiftUI

// MARK: - Appointment Prep Detail View
/// Read/edit/export view for a saved appointment-prep report.
struct AppointmentPrepDetailView: View {
    @ObservedObject var manager: AppointmentPrepManager
    @Environment(\.dismiss) private var dismiss

    @State private var prep: AppointmentPrep
    @State private var isEditing = false
    @State private var showingRegenerate = false
    @State private var showingDeleteConfirm = false

    var showsCloseButton: Bool = false

    init(prep: AppointmentPrep, manager: AppointmentPrepManager, showsCloseButton: Bool = false) {
        self.manager = manager
        self.showsCloseButton = showsCloseButton
        _prep = State(initialValue: prep)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if prep.hasGeneratedContent {
                    PrepSectionCard(
                        title: "Timeline",
                        systemImage: "clock.arrow.circlepath",
                        accent: BisonTheme.sage,
                        content: $prep.timeline,
                        isEditing: isEditing
                    )
                    PrepSectionCard(
                        title: "Questions for the Doctor",
                        systemImage: "questionmark.bubble",
                        accent: BisonTheme.gold,
                        content: $prep.questions,
                        isEditing: isEditing
                    )
                    PrepSectionCard(
                        title: "Relevant Info",
                        systemImage: "info.circle",
                        accent: BisonTheme.steel,
                        content: $prep.relevantInfo,
                        isEditing: isEditing
                    )
                } else {
                    ContentUnavailableView(
                        "No report yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Regenerate to produce a timeline, questions, and relevant info.")
                    )
                }

                inputsCard
            }
            .padding()
        }
        .background(BisonTheme.appBackground)
        .navigationTitle(prep.resolvedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingRegenerate) {
            AppointmentPrepEditorView(manager: manager, existingPrep: prep) { updated in
                prep = updated
            }
        }
        .confirmationDialog("Delete this appointment prep?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await manager.delete(prep)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(status: prep.status)
                Spacer()
                Text("Updated \(prep.lastModified, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let date = prep.appointmentDate {
                Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.subheadline)
            }
            if let provider = prep.providerName, !provider.isEmpty {
                Label(provider, systemImage: "stethoscope")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BisonTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Inputs (read-only summary)

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Inputs")
                .font(.headline)
            inputRow("Symptoms", prep.symptoms)
            if !prep.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputRow("Additional Notes", prep.notes)
            }
            if !prep.medications.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputRow("Medications", prep.medications)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BisonTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func inputRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isEditing {
                Button("Save") {
                    prep.lastModified = Date()
                    Task { try? await manager.save(prep) }
                    isEditing = false
                }
                .accessibilityIdentifier("prep.detail.save")
            } else {
                Menu {
                    ShareLink(item: prep.exportText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = prep.exportText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        PrepPrinter.print(prep.exportText, jobName: prep.resolvedTitle)
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    Divider()
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit Report", systemImage: "pencil")
                    }
                    Button {
                        showingRegenerate = true
                    } label: {
                        Label("Edit Inputs & Regenerate", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Report actions")
                .accessibilityIdentifier("prep.detail.menu")
            }
        }

        if showsCloseButton {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") { dismiss() }
            }
        }
    }
}

// MARK: - Prep Section Card
/// Displays one generated section; editable text when `isEditing` is true.
struct PrepSectionCard: View {
    let title: String
    let systemImage: String
    var accent: Color = BisonTheme.gold
    @Binding var content: String
    var isEditing: Bool = false
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if isLoading && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Generating…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isEditing {
                TextEditor(text: $content)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(BisonTheme.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(content.isEmpty ? "—" : content)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(BisonTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: PrepStatus

    private var color: Color {
        switch status {
        case .draft: return BisonTheme.steel
        case .generating: return BisonTheme.gold
        case .complete: return BisonTheme.sage
        }
    }

    var body: some View {
        Text(status.displayName.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Printing Helper
enum PrepPrinter {
    @MainActor
    static func print(_ text: String, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = jobName
        controller.printInfo = printInfo

        let formatter = UISimpleTextPrintFormatter(text: text)
        formatter.perPageContentInsets = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        controller.printFormatter = formatter
        controller.present(animated: true, completionHandler: nil)
    }
}
