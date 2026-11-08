import SwiftUI
import VisionKit
import PhotosUI

// Import all view components
// Note: These should be automatically available in the same module,
// but explicit imports help with build issues

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSection: AppSection = .health
    /// See `appShell`: chosen at launch and held, so rotation never changes it.
    @State private var launchTabBarPlacement: AdaptableTabBarPlacement?

    /// The review sheets live here, at the root, not in `DocumentsView`.
    ///
    /// They used to belong to `DocumentsView`, and `HealthTabView` swaps that view out with
    /// a `switch` when the user taps another segment. Two consequences, both real:
    ///
    /// - A review that arrived while the user was elsewhere set `pendingImportReview` on a
    ///   view that no longer existed. That is what the `initial: true` observers were added
    ///   to work around — they let a rebuilt view notice a value that was already set.
    /// - `restorePendingImportReviews()` ran from a `.task` on the same view, so a lab
    ///   import left un-reviewed by the previous session only resurfaced once the user
    ///   happened to open the Documents tab. The v13 commit claimed these were "offered
    ///   again on launch"; they were not, and that overstatement is what became item 31.
    ///
    /// At the root the sheets outlive every tab change, so the observers are a plain
    /// reaction to new state rather than a workaround for a destroyed view.
    @StateObject private var documentProcessor = DocumentProcessor.shared
    @State private var showingImportReview = false
    @State private var showingGeneticTestReview = false

    var body: some View {
        ZStack(alignment: .top) {
            appShell
                .tint(BisonTheme.goldText)
            .withErrorHandling() // Add global error handling

            // Global offline indicator
            VStack {
                OfflineIndicatorView()
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
        .sheet(isPresented: $showingImportReview) {
            if let review = documentProcessor.pendingImportReview {
                BloodTestImportReviewView(
                    importGroups: Binding(
                        get: { review.importGroups },
                        set: { _ in }
                    ),
                    autoAcceptedGroups: review.autoAcceptedGroups,
                    onComplete: { selectedGroups in
                        // Close first, then do the work. The sheet is driven by
                        // `showingImportReview`, and the view's `dismiss()` does not clear
                        // that binding — so leaving it true across an await (a database
                        // save) leaves a window in which the observer can re-present the
                        // sheet the user just dismissed. A tap on Import then looks like it
                        // did nothing.
                        showingImportReview = false
                        Task {
                            await documentProcessor.completeImportReview(review, selectedGroups: selectedGroups)
                        }
                    },
                    onCancel: {
                        // Cancel = discard this review; promote the next queued one.
                        documentProcessor.discardPendingImportReview(for: review.documentId)
                        showingImportReview = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingGeneticTestReview) {
            if let review = documentProcessor.pendingGeneticTestReview {
                GeneticTestImportReviewView(review: review) { acceptedIssueIDs, skippedIssueIDs in
                    Task {
                        await documentProcessor.completeGeneticTestReview(
                            review,
                            acceptedIssueIDs: acceptedIssueIDs,
                            skippedIssueIDs: skippedIssueIDs
                        )
                        showingGeneticTestReview = false
                    }
                }
            }
        }
        .onChange(of: documentProcessor.pendingImportReview, initial: true) { _, newValue in
            showingImportReview = newValue != nil
        }
        .onChange(of: documentProcessor.pendingGeneticTestReview, initial: true) { _, newValue in
            showingGeneticTestReview = newValue != nil
        }
        .task {
            // Offer back any lab import the previous session left un-reviewed. Before v13
            // these lived only in memory, so a cancel or a force-quit discarded every
            // extracted value and only re-processing the document recovered them. Running
            // it here means the offer arrives wherever the user happens to be.
            await documentProcessor.restorePendingImportReviews()
        }
    }

    /// One container for every width. `.sidebarAdaptable` is a tab bar on compact width
    /// and a system sidebar on regular width, from the same view tree.
    ///
    /// It used to be two trees, a `TabView` or a hand-built sidebar `HStack`, chosen by size
    /// class. Changing size class swapped one for the other and rebuilt everything inside, so
    /// every navigation path, scroll position, open chat and half-filled form was lost. On
    /// iPad that took a Split View resize; on iPhone Duo it happens every time the phone is
    /// opened or closed. One tree keeps that state, and system bars and sidebar are what
    /// Duo moves to the side of the display and keeps clear of the fold.
    ///
    /// iPad in portrait starts with the sidebar closed (owner decision, 2026-11-07): there a
    /// sidebar is drawn over the content rather than beside it, so it starts as the top tab
    /// bar, whose sidebar button opens it. Landscape iPad starts with the sidebar.
    ///
    /// The choice is made once, from the window's shape at launch, and then held; the
    /// `GeometryReader` is there so the very first layout already knows that shape. It must
    /// not follow rotation: changing the placement on a live tab view from sidebar to tab bar
    /// left the floating tab bar drawn over the navigation bars and stopped tab taps landing
    /// (iOS 26.5). Rotation is left to the system, which on a portrait launch brings the
    /// sidebar out in landscape and puts it away again in portrait.
    ///
    /// Everything else keeps the sidebar: the open iPhone Duo is a phone and not covered by
    /// the decision, and on a Mac an iPad app's window can be any shape.
    private var appShell: some View {
        GeometryReader { proxy in
            tabShell(placement: launchTabBarPlacement ?? Self.tabBarPlacement(for: proxy.size))
                .onAppear {
                    if launchTabBarPlacement == nil {
                        launchTabBarPlacement = Self.tabBarPlacement(for: proxy.size)
                    }
                }
        }
    }

    private static func tabBarPlacement(for size: CGSize) -> AdaptableTabBarPlacement {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad && !PlatformCapabilities.isRunningOnMac
        return isPad && size.height > size.width ? .tabBar : .sidebar
    }

    private func tabShell(placement: AdaptableTabBarPlacement) -> some View {
        TabView(selection: $selectedSection) {
            ForEach(AppSection.allCases) { section in
                Tab(section.title, systemImage: section.systemImage, value: section) {
                    section.destination
                        .background(BisonTheme.appBackground)
                        .accessibilityIdentifier("tab.\(section.rawValue)")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(placement)
        .tabViewSidebarHeader { AppSidebarHeader() }
        .tabViewSidebarFooter { AppSidebarFooter() }
        .background(BisonTheme.appBackground)
        .toolbarBackground(BisonTheme.sidebarBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(BisonTheme.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - App Navigation
private enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case health
    case appointmentPrep
    case chat
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health: return "Health"
        case .appointmentPrep: return "Prep"
        case .chat: return "AI Chat"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .health: return "heart.text.square.fill"
        case .appointmentPrep: return "stethoscope"
        case .chat: return "message.fill"
        case .settings: return "slider.horizontal.3"
        }
    }

    /// `@MainActor` because it constructs `View`s whose initializers are main-actor
    /// isolated; this enum is not itself a `View`, so it gets no isolation by inference.
    @MainActor
    @ViewBuilder
    var destination: some View {
        switch self {
        case .health:
            HealthTabView()
        case .appointmentPrep:
            AppointmentPrepView()
        case .chat:
            ChatView()
        case .settings:
            SettingsView()
        }
    }
}

/// App name and mark at the top of the regular-width sidebar.
private struct AppSidebarHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("BisonHealthAI_ProIcon_1024")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BisonTheme.gold.opacity(0.35), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Bison Health")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BisonTheme.primaryText)
                    .lineLimit(1)

                Text("AI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BisonTheme.goldText)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// The privacy note at the foot of the regular-width sidebar.
private struct AppSidebarFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(BisonTheme.sage)
                .frame(width: 8, height: 8)

            Text("Private by design")
                .font(.caption)
                .foregroundStyle(BisonTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BisonTheme.panelBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Health Data View
struct HealthDataView: View {
    @StateObject private var healthDataManager = HealthDataManager.shared
    @State private var showingPersonalInfoEditor = false
    @State private var showingBloodTestEntry = false
    @State private var editingBloodTest: BloodTestResult?
    @State private var showingVitalEntry: VitalType?
    @State private var editingVital: (type: VitalType, index: Int)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        PlatformCapabilities.usesExpandedLayout(horizontalSizeClass: horizontalSizeClass)
    }

    /// `HealthTabView` owns the navigation bar for both of its segments — it puts the
    /// segment switcher in the principal position so there is exactly one bar — and it is
    /// the only thing that constructs this view. The `embedInNavigation: true` branch that
    /// used to live here wrapped the content in its own `NavigationStack` and was therefore
    /// unreachable; it is gone rather than left looking like a supported mode.
    var body: some View {
        healthContent
    }

    private var healthContent: some View {
            List {
                PersonalInfoSection(
                    personalInfo: healthDataManager.personalInfo,
                    onEdit: {
                        showingPersonalInfoEditor = true
                    }
                )

                VitalsSummarySection(personalInfo: healthDataManager.personalInfo)

                BloodTestsSection(
                    bloodTests: $healthDataManager.bloodTests,
                    onAddNew: {
                        showingBloodTestEntry = true
                    },
                    onEdit: { editingBloodTest = $0 },
                    onDelete: { bloodTest in
                        Task {
                            do {
                                try await healthDataManager.deleteBloodTest(bloodTest)
                            } catch {
                                ErrorHandler.shared.handle(error, context: "Health records", severity: .error)
                            }
                        }
                    }
                )

                // Genetic test reports remain in Records with their source
                // document and can surface a review badge for uncertain OCR
                // or unrecognized findings.
                GeneticTestsSection(
                    geneticTests: $healthDataManager.geneticTestDocuments
                )

                // Imaging Reports Section
                ImagingReportsSection(
                    imagingReports: $healthDataManager.imagingReports,
                    onDocumentTap: { _ in }
                )

                // Medical Visits Section
                HealthCheckupsSection(
                    healthCheckups: $healthDataManager.healthCheckups,
                    onDocumentTap: { _ in }
                )
            }
            .navigationTitle("Health Data")
            .navigationBarTitleDisplayMode(.inline)
            .dynamicType(.body, isIPad: isIPad)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Personal Info") {
                            showingPersonalInfoEditor = true
                        }
                        .voiceOverLabel(
                            "Add Personal Information",
                            hint: "Opens form to edit personal health information"
                        )
                        Button("Lab Results") {
                            showingBloodTestEntry = true
                        }
                        .voiceOverLabel(
                            "Add Lab Results",
                            hint: "Opens form to add new blood test results"
                        )
                        Divider()
                        Button("Imaging Report") {
                            // Placeholder for future implementation
                        }
                        .disabled(true)
                        .voiceOverLabel(
                            "Add Imaging Report",
                            hint: "Feature coming soon"
                        )
                        Button("Medical Visit") {
                            // Placeholder for future implementation
                        }
                        .disabled(true)
                        .voiceOverLabel(
                            "Add Medical Visit",
                            hint: "Feature coming soon"
                        )
                    } label: {
                        Label("Add Health Data", systemImage: "plus")
                    }
                    .voiceOverLabel(
                        "Add Health Data",
                        hint: "Menu to add new health data entries",
                        traits: [.button]
                    )
                }
                .keptVisibleLongest()
            }
            .refreshable {
                await healthDataManager.loadHealthData()
            }
            .sheet(isPresented: $showingPersonalInfoEditor) {
                PersonalInfoEditorView(
                    personalInfo: healthDataManager.personalInfo,
                    onSave: { info in
                        Task {
                            do {
                                try await healthDataManager.savePersonalInfo(info)
                            } catch {
                                ErrorHandler.shared.handle(error, context: "Health records", severity: .error)
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showingBloodTestEntry) {
                BloodTestEntryView(
                    onSave: { bloodTest in
                        Task {
                            do {
                                try await healthDataManager.addBloodTest(bloodTest)
                            } catch {
                                ErrorHandler.shared.handle(error, context: "Health records", severity: .error)
                            }
                        }
                    }
                )
            }
            .sheet(item: $editingBloodTest) { bloodTest in
                BloodTestEntryView(bloodTest: bloodTest) { updated in
                    Task {
                        do {
                            try await healthDataManager.updateBloodTest(updated)
                        } catch {
                            ErrorHandler.shared.handle(error, context: "Health records", severity: .error)
                        }
                    }
                }
            }
            .sheet(item: $showingVitalEntry) { vitalType in
                VitalEntryView(
                    vitalType: vitalType,
                    existingReading: nil,
                    personalInfo: healthDataManager.personalInfo,
                    onSave: { updatedInfo in
                        Task {
                            do {
                                try await healthDataManager.savePersonalInfo(updatedInfo)
                            } catch {
                                ErrorHandler.shared.handle(error, context: "Health records", severity: .error)
                            }
                        }
                    }
                )
            }
            .sheet(item: Binding(
                get: { editingVital.map { EditingVitalWrapper(type: $0.type, index: $0.index) } },
                set: { editingVital = $0.map { ($0.type, $0.index) } }
            )) { wrapper in
                VitalEntryView(
                    vitalType: wrapper.type,
                    existingReading: (wrapper.type, wrapper.index),
                    personalInfo: healthDataManager.personalInfo,
                    onSave: { updatedInfo in
                        Task {
                            do {
                                try await healthDataManager.savePersonalInfo(updatedInfo)
                            } catch {
                                ErrorHandler.shared.handle(error, context: "Health records", severity: .error)
                            }
                        }
                    }
                )
            }
            .keyboardNavigable()
    }

    // MARK: - Vital Management Helpers
    private func deleteVitalReading(type: VitalType, index: Int) async {
        guard var info = healthDataManager.personalInfo else { return }

        switch type {
        case .bloodPressure:
            if index < info.bloodPressureReadings.count {
                info.bloodPressureReadings.remove(at: index)
            }
        case .heartRate:
            if index < info.heartRateReadings.count {
                info.heartRateReadings.remove(at: index)
            }
        case .weight:
            if index < info.weightReadings.count {
                info.weightReadings.remove(at: index)
            }
        case .bodyTemperature:
            if index < info.bodyTemperatureReadings.count {
                info.bodyTemperatureReadings.remove(at: index)
            }
        case .oxygenSaturation:
            if index < info.oxygenSaturationReadings.count {
                info.oxygenSaturationReadings.remove(at: index)
            }
        case .respiratoryRate:
            if index < info.respiratoryRateReadings.count {
                info.respiratoryRateReadings.remove(at: index)
            }
        case .sleep:
            if index < info.sleepData.count {
                info.sleepData.remove(at: index)
            }
        }

        do {
            try await healthDataManager.savePersonalInfo(info)
        } catch {
            AppLog.shared.ui("Failed to delete vital reading: \(error)", level: .error)
        }
    }
}

// MARK: - Editing Vital Wrapper
struct EditingVitalWrapper: Identifiable {
    let id = UUID()
    let type: VitalType
    let index: Int
}

// MARK: - VitalType Identifiable Extension
extension VitalType: Identifiable {
    var id: String {
        switch self {
        case .bloodPressure: return "bloodPressure"
        case .heartRate: return "heartRate"
        case .weight: return "weight"
        case .bodyTemperature: return "bodyTemperature"
        case .oxygenSaturation: return "oxygenSaturation"
        case .respiratoryRate: return "respiratoryRate"
        case .sleep: return "sleep"
        }
    }
}

// MARK: - Documents View
struct DocumentsView<ListHeader: View>: View {
    /// Pinned above the list column: the Records/Documents switch from `HealthTabView`.
    let listHeader: ListHeader

    @StateObject private var documentManager = DocumentManager(
        documentImporter: DocumentImporter.shared,
        documentProcessor: DocumentProcessor.shared,
        databaseManager: DatabaseManager.shared,
        fileSystemManager: FileSystemManager.shared
    )
    @StateObject private var documentProcessor = DocumentProcessor.shared

    @State private var showingDocumentPicker = false
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var showingFilterView = false
    @State private var showingBatchProcessing = false
    /// The open document, by id. The detail column looks it up in `documentManager.documents`
    /// on every render, so it shows processing progress as it happens and falls back to the
    /// placeholder once the document is deleted. (The sheet this replaced held a snapshot.)
    @State private var selectedDocumentID: UUID?
    /// Which column a collapsed split view shows: the list until a document is tapped.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var viewMode: DocumentViewMode = .list
    @State private var showingDocumentTypeSelector = false
    @State private var pendingDocumentForCategory: MedicalDocument?
    /// All documents awaiting category selection. Without a queue, a
    /// multi-file import only ever processed the first document.
    @State private var pendingCategoryDocuments: [MedicalDocument] = []
    @State private var activeAutoImportSummary: AutoImportSummary?
    @State private var autoImportBannerDismissTask: Task<Void, Never>?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Owned here and handed to the list column, not read from the environment. This view
    /// sits *outside* its split view, so an environment read would see its ancestor's edit
    /// mode, while the Edit button and the rows inside the column would see the column's —
    /// and Batch, which checks it, would never appear. One binding keeps them all in step.
    @State private var editMode: EditMode = .inactive

    private var isIPad: Bool {
        PlatformCapabilities.usesExpandedLayout(horizontalSizeClass: horizontalSizeClass)
    }

    private var supportsDocumentScanning: Bool {
        PlatformCapabilities.supportsDocumentScanning
    }

    /// One split view at every width, as in `ChatView`: the list beside the open document on
    /// iPad and the open iPhone Duo, collapsing to a stack with the document pushed on
    /// compact width. One tree means opening or closing a Duo keeps the open document.
    ///
    /// Before this, landscape iPad got a full-width list with the document in a form sheet
    /// (WS-09-03), and the owner chose side by side on 2026-11-07.
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            documentsPrimaryContent
                .environment(\.editMode, $editMode)
                .pinnedSegmentSwitcher(listHeader)
                // No maximum, for the same reason as the chat list: on a partly folded
                // Duo the system widens this column to the fold.
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            documentDetailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentCameraView { scan in
                Task {
                    if let document = await documentManager.importScannedDocument(scan) {
                        pendingDocumentForCategory = document
                        selectedDocumentID = document.id
                        showingDocumentTypeSelector = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            // Keep in sync with DocumentImporter.isValidDocumentType: the
            // importer rejects anything else (e.g. plain text) after picking.
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            handleFileImportResult(result)
        }
        .photosPicker(
            isPresented: $showingPhotosPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, photos in
            handleSelectedPhotos(photos)
        }
        .sheet(isPresented: $showingFilterView) {
            DocumentFilterView(documentManager: documentManager)
        }
        .sheet(isPresented: $showingBatchProcessing) {
            BatchProcessingView(
                documentManager: documentManager,
                documentProcessor: documentProcessor
            )
        }
        .onChange(of: documentProcessor.lastAutoImportSummary, initial: true) { _, newValue in
            guard let summary = newValue else { return }
            activeAutoImportSummary = summary

            // Auto-dismiss the banner after a while
            autoImportBannerDismissTask?.cancel()
            autoImportBannerDismissTask = Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if !Task.isCancelled {
                    activeAutoImportSummary = nil
                    documentProcessor.lastAutoImportSummary = nil
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let summary = activeAutoImportSummary {
                autoImportBanner(summary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: activeAutoImportSummary)
        .task {
            guard AppTestRuntime.shouldSeedLabReport else { return }

            for _ in 0..<20 {
                await documentManager.refreshDocuments()
                if documentManager.documents.contains(where: { $0.fileName == "ui-test-lab-report.pdf" }) {
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .sheet(isPresented: $showingDocumentTypeSelector) {
            if let document = pendingDocumentForCategory {
                DocumentTypeSelectorView(
                    fileName: document.fileName,
                    selectedCategory: Binding(
                        get: { document.documentCategory },
                        set: { _ in }
                    ),
                    onConfirm: { category in
                        Task {
                            await documentManager.setDocumentCategoryAndProcess(document.id, category: category)
                            pendingDocumentForCategory = nil
                            showingDocumentTypeSelector = false
                            // Present the selector for the next queued document.
                            // Re-presenting (rather than swapping sheet content)
                            // gives DocumentTypeSelectorView fresh @State selection.
                            pendingCategoryDocuments.removeAll { $0.id == document.id }
                            if let next = pendingCategoryDocuments.first {
                                pendingDocumentForCategory = next
                                selectedDocumentID = next.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    showingDocumentTypeSelector = true
                                }
                            }
                        }
                    }
                )
            }
        }
    }

    private var documentsPrimaryContent: some View {
        Group {
            if documentManager.documents.isEmpty {
                DocumentsEmptyStateView(
                    supportsDocumentScanning: supportsDocumentScanning,
                    didFailToLoad: documentManager.didFailToLoad,
                    onScanDocument: showDocumentScanner,
                    onImportFile: showDocumentPicker,
                    onImportPhotos: showPhotosPicker,
                    onRetry: {
                        Task { await documentManager.loadDocuments() }
                    }
                )
            } else {
                VStack(spacing: 0) {
                    // Search and filter bar
                    if !documentManager.documents.isEmpty {
                        searchAndFilterBar
                    }

                    // Processing progress bar
                    if documentProcessor.isProcessing {
                        processingProgressBar
                    }

                    // Document content
                    documentContent
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .dynamicType(.body, isIPad: isIPad)
        .toolbar {
                // Items in the group directly, not wrapped in an HStack: a custom view in a
                // toolbar is never moved to the vertical bar on iPhone Duo.
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !documentManager.documents.isEmpty {
                        EditButton()
                            .voiceOverLabel(
                                "Edit Documents",
                                hint: "Toggle edit mode to select documents",
                                traits: [.button]
                            )

                        if editMode.isEditing && !documentManager.selectedDocuments.isEmpty {
                            Button("Batch", systemImage: "square.stack.3d.up") {
                                showingBatchProcessing = true
                            }
                            .voiceOverLabel(
                                "Batch Process",
                                hint: "Process selected documents together",
                                traits: [.button]
                            )
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !documentManager.documents.isEmpty {
                        // View mode toggle (iPad only)
                        // A button that names the other mode rather than a fixed-width segmented
                        // picker, which as a custom view could not join a vertical bar.
                        if isIPad {
                            Button(
                                viewMode == .list ? "Grid View" : "List View",
                                systemImage: viewMode == .list ? "square.grid.2x2" : "list.bullet"
                            ) {
                                viewMode = viewMode == .list ? .grid : .list
                            }
                            // No fixed label: the title is the destination ("Grid View" /
                            // "List View"), which VoiceOver should announce.
                            .accessibilityHint("Switches how documents are shown")
                            .accessibilityIdentifier("documents.viewModeToggle")
                        }
                    }

                    Menu {
                        if supportsDocumentScanning {
                            Button("Scan Document", systemImage: "camera.viewfinder") {
                                showDocumentScanner()
                            }
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .voiceOverLabel(
                                "Scan Document",
                                hint: "Use camera to scan a document",
                                traits: [.button]
                            )
                        }
                        Button("Import File", systemImage: "folder") {
                            showDocumentPicker()
                        }
                        .keyboardShortcut("o", modifiers: [.command])
                        .voiceOverLabel(
                            "Import File",
                            hint: "Import document from Files app",
                            traits: [.button]
                        )
                        Button("Import Photos", systemImage: "photo.on.rectangle") {
                            showPhotosPicker()
                        }
                        .voiceOverLabel(
                            "Import Photos",
                            hint: "Import photos from Photos app",
                            traits: [.button]
                        )

                        if !documentManager.documents.isEmpty {
                            Divider()

                            Button("Process All Pending", systemImage: "gearshape.2") {
                                Task {
                                    await documentManager.processAllPendingDocuments()
                                }
                            }
                            .voiceOverLabel(
                                "Process All Pending",
                                hint: "Process all documents waiting to be analyzed",
                                traits: [.button]
                            )

                            Button("Retry Failed", systemImage: "arrow.clockwise") {
                                Task {
                                    await documentManager.retryFailedDocuments()
                                }
                            }
                            .voiceOverLabel(
                                "Retry Failed",
                                hint: "Retry processing documents that failed",
                                traits: [.button]
                            )
                        }
                    } label: {
                        Label("Add Document", systemImage: "plus")
                    }
                    .voiceOverLabel(
                        "Add Document",
                        hint: "Menu to add new documents",
                        traits: [.button]
                    )
                }
                .keptVisibleLongest()
            }
            .refreshable {
                await documentManager.refreshDocuments()
            }
            .keyboardNavigable()
    }

    // MARK: - Import Review Handler
    private func showDocumentScanner() {
        guard supportsDocumentScanning else {
            AppLog.shared.ui("Document scanner is unavailable on this platform", level: .warning)
            return
        }

        AppLog.shared.ui("Showing camera for document scanning")
        showingCamera = true
    }

    private func showDocumentPicker() {
        AppLog.shared.ui("Triggering document picker (LaunchServices console errors are normal in development)")
        showingDocumentPicker = true
    }

    private func showPhotosPicker() {
        AppLog.shared.ui("Showing photos picker")
        showingPhotosPicker = true
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        AppLog.shared.ui("File importer result received")

        switch result {
        case .success(let urls):
            AppLog.shared.ui("File importer successful, \(urls.count) URLs received")
            for (index, url) in urls.enumerated() {
                AppLog.shared.ui("URL \(index + 1): \(url)")
            }

            Task {
                AppLog.shared.ui("Starting document import process...")
                let importedDocs = await documentManager.importDocuments(from: urls)
                AppLog.shared.ui("Document import process completed")

                // Queue EVERY imported document for category selection —
                // a single slot would leave all but the first unprocessed.
                // APPEND: a replacing assignment would strand documents still
                // queued from a previous import batch.
                if !importedDocs.isEmpty {
                    pendingCategoryDocuments.append(contentsOf: importedDocs)
                    if pendingDocumentForCategory == nil {
                        pendingDocumentForCategory = pendingCategoryDocuments.first
                        selectedDocumentID = pendingCategoryDocuments.first?.id
                    }
                    showingDocumentTypeSelector = true
                }
            }

        case .failure(let error):
            AppLog.shared.ui("File import failed with error: \(error)", level: .error)
            AppLog.shared.ui("Error type: \(type(of: error))", level: .error)
            AppLog.shared.ui("Error description: \(error.localizedDescription)", level: .error)

            // Check for LaunchServices errors
            if error.localizedDescription.contains("OSStatusErrorDomain Code=-54") ||
                error.localizedDescription.contains("database") ||
                error.localizedDescription.contains("LaunchServices") ||
                error.localizedDescription.contains("permission") {
                AppLog.shared.ui("LaunchServices error detected (normal in development/simulator environment)")
                AppLog.shared.ui("This error doesn't affect document import functionality")
            } else {
                AppLog.shared.ui("Unexpected file import error that may need attention", level: .error)
            }
        }
    }

    private func handleSelectedPhotos(_ photos: [PhotosPickerItem]) {
        guard !photos.isEmpty else { return }

        Task {
            var importedDocs: [MedicalDocument] = []

            for photo in photos {
                if let data = try? await photo.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    do {
                        let doc = try await DocumentImporter.shared.importImage(image)
                        importedDocs.append(doc)
                    } catch {
                        AppLog.shared.ui("Failed to import photo: \(error)", level: .error)
                    }
                }
            }

            // Add to document manager
            documentManager.documents.append(contentsOf: importedDocs)
            documentManager.documents.sort { $0.importedAt > $1.importedAt }

            // Show category selector for first document
            // Queue EVERY imported photo for category selection — a single
            // slot would leave all but the first unprocessed. APPEND so a
            // second import never strands documents still queued.
            if !importedDocs.isEmpty {
                pendingCategoryDocuments.append(contentsOf: importedDocs)
                if pendingDocumentForCategory == nil {
                    pendingDocumentForCategory = pendingCategoryDocuments.first
                    selectedDocumentID = pendingCategoryDocuments.first?.id
                }
                showingDocumentTypeSelector = true
            }

            selectedPhotos = []
        }
    }

    private func findStandardKey(for testName: String) -> String? {
        if let match = BloodTestResult.matchLabParameter(name: testName, testType: .blood) {
            return match.key
        }
        return BloodTestResult.matchLabParameter(name: testName, testType: .urine)?.key
    }

    // MARK: - Auto-Import Banner

    private func autoImportBanner(_ summary: AutoImportSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Imported \(summary.importedCount) lab value\(summary.importedCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(summary.documentName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Undo") {
                Task {
                    await undoAutoImport(summary)
                }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityLabel("Undo automatic import")
            .accessibilityHint("Removes the \(summary.importedCount) lab values that were just imported")
            .accessibilityIdentifier("undoAutoImportButton")

            Button {
                dismissAutoImportBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Dismiss import notification")
            .accessibilityIdentifier("dismissAutoImportBannerButton")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Imported \(summary.importedCount) lab values from \(summary.documentName)")
    }

    private func dismissAutoImportBanner() {
        autoImportBannerDismissTask?.cancel()
        activeAutoImportSummary = nil
        documentProcessor.lastAutoImportSummary = nil
    }

    private func undoAutoImport(_ summary: AutoImportSummary) async {
        let healthDataManager = HealthDataManager.shared
        do {
            if let bloodTest = healthDataManager.bloodTests.first(where: { $0.id == summary.bloodTestId }) {
                try await healthDataManager.deleteBloodTest(bloodTest)
                AppLog.shared.ui("Undid auto-import of \(summary.importedCount) lab values from '\(summary.documentName)'")
            } else {
                AppLog.shared.ui("Undo requested but blood test \(summary.bloodTestId) not found", level: .warning)
            }
        } catch {
            AppLog.shared.ui("Failed to undo auto-import: \(error)", level: .error)
        }
        dismissAutoImportBanner()
    }

    // MARK: - Search and Filter Bar

    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AccessibilityColors.secondaryText)
                            .accessibilityHidden(true)

                        TextField("Search documents...", text: $documentManager.searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .voiceOverLabel(
                                "Search Documents",
                                hint: "Type to search for documents",
                                traits: [.searchField]
                            )
                            .accessibilityIdentifier("documents.searchField")

                        if !documentManager.searchText.isEmpty {
                            Button("Clear") {
                                documentManager.searchText = ""
                            }
                            .font(.caption)
                            .foregroundColor(AccessibilityColors.info)
                            .touchTarget()
                            .voiceOverLabel(
                                "Clear Search",
                                hint: "Clears the search text",
                                traits: [.button]
                            )
                        }
                    }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                Button("Filter") {
                    showingFilterView = true
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(hasActiveFilters ? AccessibilityColors.info : AccessibilityColors.tertiaryBackground)
                .foregroundColor(hasActiveFilters ? AccessibilityColors.buttonText : AccessibilityColors.info)
                .cornerRadius(8)
                .touchTarget()
                .voiceOverLabel(
                    "Filter Documents",
                    hint: "Open filter options to refine document list",
                    value: hasActiveFilters ? "Filters active" : nil,
                    traits: [.button]
                )
            }

            // Active filters display
            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let status = documentManager.filterStatus {
                            ActiveFilterChip(title: status.displayName) {
                                documentManager.filterStatus = nil
                            }
                        }

                        if let type = documentManager.filterType {
                            ActiveFilterChip(title: type.rawValue.capitalized) {
                                documentManager.filterType = nil
                            }
                        }

                        if documentManager.sortOrder != .dateDescending {
                            ActiveFilterChip(title: documentManager.sortOrder.displayName) {
                                documentManager.sortOrder = .dateDescending
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Processing Progress Bar

    private var processingProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Processing documents...")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(documentProcessor.processingProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: documentProcessor.processingProgress)
                .progressViewStyle(LinearProgressViewStyle())
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Document Content

    @ViewBuilder
    private var documentContent: some View {
        switch viewMode {
        case .list:
            DocumentListView(
                documents: documentManager.filteredDocuments,
                selectedDocuments: $documentManager.selectedDocuments,
                onDocumentTap: openDocument
            )
        case .grid:
            DocumentGridView(
                documents: documentManager.filteredDocuments,
                selectedDocuments: $documentManager.selectedDocuments,
                onDocumentTap: openDocument
            )
        }
    }

    private func openDocument(_ document: MedicalDocument) {
        selectedDocumentID = document.id
        preferredCompactColumn = .detail
    }

    /// The open document, or a prompt to pick one.
    @ViewBuilder
    private var documentDetailColumn: some View {
        if let id = selectedDocumentID,
           let document = documentManager.documents.first(where: { $0.id == id }) {
            DocumentDetailView(
                document: document,
                documentManager: documentManager,
                documentProcessor: documentProcessor
            )
            // Fresh editor state per document; the same document re-rendering with new
            // processing status keeps it.
            .id(document.id)
        } else {
            ContentUnavailableView(
                "No Document Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a document from the list to see it here.")
            )
            .background(BisonTheme.appBackground)
        }
    }

    // MARK: - Helper Properties

    private var hasActiveFilters: Bool {
        documentManager.filterStatus != nil ||
        documentManager.filterType != nil ||
        documentManager.sortOrder != .dateDescending ||
        !documentManager.searchText.isEmpty
    }

    private func calculateTotalDocumentsSize() -> Int64? {
        guard !documentManager.documents.isEmpty else { return nil }

        var totalSize: Int64 = 0
        for document in documentManager.documents {
            totalSize += document.fileSize
        }

        return totalSize > 0 ? totalSize : nil
    }
}

// MARK: - Supporting Types and Views

enum DocumentViewMode {
    case list
    case grid
}

struct ActiveFilterChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(BisonTheme.gold)
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}

// MARK: - Chat View
struct ChatView: View {
    @StateObject private var chatManager = AIChatManager(
        healthDataManager: HealthDataManager.shared,
        databaseManager: DatabaseManager.shared
    )
    @State private var showingContextSelector = false
    @State private var searchText = ""
    @State private var selectedConversationId: UUID?
    /// Which column a collapsed split view shows. Starts on the chat, as the phone layout
    /// always did; Back reaches the conversation list.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        PlatformCapabilities.usesExpandedLayout(horizontalSizeClass: horizontalSizeClass)
    }

    /// One split view at every width. It collapses to a stack on compact width by itself.
    ///
    /// This used to be a `NavigationSplitView` or a `NavigationStack` chosen by size class,
    /// with a sheet standing in for the sidebar on phones. Changing size class swapped the
    /// trees, so opening an iPhone Duo mid-conversation dropped the open chat and its draft.
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            ConversationSidebarView(
                conversations: chatManager.conversations,
                selectedConversationId: $selectedConversationId,
                searchText: $searchText,
                onSelectConversation: { conversation in
                    chatManager.selectConversation(conversation)
                    selectedConversationId = conversation.id
                    preferredCompactColumn = .detail
                },
                onNewConversation: startNewConversation,
                onDeleteConversation: { conversation in
                    Task {
                        do {
                            try await chatManager.deleteConversation(conversation)
                            if selectedConversationId == conversation.id {
                                selectedConversationId = nil
                            }
                            if chatManager.currentConversation?.id == conversation.id {
                                chatManager.currentConversation = nil
                            }
                        } catch {
                            ErrorHandler.shared.handle(error, context: "Chat", severity: .error)
                        }
                    }
                }
            )
            // No maximum: on a partly folded iPhone Duo the system widens this column to
            // the fold, and a cap (this was 400 pt, half the open display is ~475 pt) left
            // the crease running through the middle of the chat.
            .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            // Also names the Back button that returns here on compact width.
            .navigationTitle("Conversations")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Conversation", systemImage: "plus", action: startNewConversation)
                        .accessibilityIdentifier("chat.sidebar.newConversation")
                }
            }
        } detail: {
            ChatDetailView(
                chatManager: chatManager,
                showingContextSelector: $showingContextSelector,
                isIPad: isIPad
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Chat", systemImage: "square.and.pencil", action: startNewConversation)
                        .keyboardShortcut("n", modifiers: [.command])
                        .accessibilityIdentifier("chat.newConversation")
                }
                .keptVisibleLongest()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingContextSelector) {
            UnifiedContextSelectorView(chatManager: chatManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await chatManager.loadConversations()
            // Skip automatic connection test on startup to avoid console noise
        }
    }

    private func startNewConversation() {
        Task {
            do {
                let conversation = try await chatManager.startNewConversation()
                selectedConversationId = conversation.id
                preferredCompactColumn = .detail
            } catch {
                ErrorHandler.shared.handle(error, context: "Chat", severity: .error)
            }
        }
    }
}


// MARK: - Vitals Summary Section
struct VitalsSummarySection: View {
    let personalInfo: PersonalHealthInfo?

    private var vitalsCount: Int {
        guard let info = personalInfo else { return 0 }
        var count = 0
        if !info.bloodPressureReadings.isEmpty { count += 1 }
        if !info.heartRateReadings.isEmpty { count += 1 }
        if !info.weightReadings.isEmpty { count += 1 }
        if !info.bodyTemperatureReadings.isEmpty { count += 1 }
        if !info.oxygenSaturationReadings.isEmpty { count += 1 }
        if !info.respiratoryRateReadings.isEmpty { count += 1 }
        if !info.sleepData.isEmpty { count += 1 }
        return count
    }

    var body: some View {
        Section {
            NavigationLink(destination: VitalsListView()) {
                HStack {
                    Image(systemName: "heart.text.square")
                        .foregroundColor(.pink)
                        .font(.title3)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Vitals")
                            .font(.headline)

                        if vitalsCount > 0 {
                            Text("\(vitalsCount) categories tracked")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No vitals data yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
