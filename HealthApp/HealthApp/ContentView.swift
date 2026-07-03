import SwiftUI
import VisionKit
import PhotosUI

// Import all view components
// Note: These should be automatically available in the same module,
// but explicit imports help with build issues

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: AppSection = .health

    private var isIPad: Bool {
        PlatformCapabilities.usesExpandedLayout(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if isIPad {
                    expandedAppShell
                } else {
                    compactTabShell
                }
            }
            .tint(BisonTheme.gold)
            .withErrorHandling() // Add global error handling

            // Global offline indicator
            VStack {
                OfflineIndicatorView()
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var compactTabShell: some View {
        TabView(selection: $selectedSection) {
            HealthTabView()
                .tabItem {
                    Image(systemName: AppSection.health.systemImage)
                        .accessibilityLabel(AppSection.health.title)
                    Text(AppSection.health.title)
                }
                .tag(AppSection.health)
                .accessibilityIdentifier("tab.health")

            AppointmentPrepView()
                .tabItem {
                    Image(systemName: AppSection.appointmentPrep.systemImage)
                        .accessibilityLabel(AppSection.appointmentPrep.title)
                    Text(AppSection.appointmentPrep.title)
                }
                .tag(AppSection.appointmentPrep)
                .accessibilityIdentifier("tab.appointmentPrep")

            ChatView()
                .tabItem {
                    Image(systemName: AppSection.chat.systemImage)
                        .accessibilityLabel(AppSection.chat.title)
                    Text(AppSection.chat.title)
                }
                .tag(AppSection.chat)
                .accessibilityIdentifier("tab.chat")

            SettingsView()
                .tabItem {
                    Image(systemName: AppSection.settings.systemImage)
                        .accessibilityLabel(AppSection.settings.title)
                    Text(AppSection.settings.title)
                }
                .tag(AppSection.settings)
                .accessibilityIdentifier("tab.settings")
        }
        .background(BisonTheme.appBackground)
        .toolbarBackground(BisonTheme.sidebarBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(BisonTheme.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var expandedAppShell: some View {
        HStack(spacing: 0) {
            AppSidebar(selectedSection: $selectedSection)
                .frame(width: 280)

            Rectangle()
                .fill(AccessibilityColors.divider.opacity(0.5))
                .frame(width: 1)

            selectedSection.destination
                .background(BisonTheme.appBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BisonTheme.appBackground)
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

    var accent: Color {
        switch self {
        case .health: return BisonTheme.sage
        case .appointmentPrep: return BisonTheme.hideBrown
        case .chat: return BisonTheme.gold
        case .settings: return BisonTheme.steel
        }
    }

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

private struct AppSidebar: View {
    @Binding var selectedSection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sidebarHeader

            VStack(spacing: 6) {
                ForEach(AppSection.allCases) { section in
                    AppSidebarItem(
                        section: section,
                        isSelected: selectedSection == section,
                        action: {
                            selectedSection = section
                        }
                    )
                }
            }

            Spacer(minLength: 24)

            sidebarFooter
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BisonTheme.sidebarBackground)
    }

    private var sidebarHeader: some View {
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
                    .foregroundStyle(BisonTheme.gold)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var sidebarFooter: some View {
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

private struct AppSidebarItem: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? BisonTheme.inkOnGold : section.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? BisonTheme.gold : section.accent.opacity(0.13))
                    )

                Text(section.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? BisonTheme.primaryText : BisonTheme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(itemBackground)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.\(section.rawValue)")
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var itemBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? BisonTheme.selectedSidebarItem : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? BisonTheme.gold.opacity(0.32) : Color.clear, lineWidth: 1)
            )
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

    /// When false (e.g. embedded in HealthTabView), renders content without its
    /// own NavigationStack so a parent can own the navigation bar.
    var embedInNavigation: Bool = true

    var body: some View {
        if embedInNavigation {
            NavigationStack { healthContent }
        } else {
            healthContent
        }
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
                            try await healthDataManager.deleteBloodTest(bloodTest)
                        }
                    }
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
                ToolbarItem(placement: .navigationBarTrailing) {
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
                        Image(systemName: "plus")
                            .touchTarget()
                    }
                    .voiceOverLabel(
                        "Add Health Data",
                        hint: "Menu to add new health data entries",
                        traits: [.button]
                    )
                }
            }
            .refreshable {
                await healthDataManager.loadHealthData()
            }
            .sheet(isPresented: $showingPersonalInfoEditor) {
                PersonalInfoEditorView(
                    personalInfo: healthDataManager.personalInfo,
                    onSave: { info in
                        Task {
                            try await healthDataManager.savePersonalInfo(info)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingBloodTestEntry) {
                BloodTestEntryView(
                    onSave: { bloodTest in
                        Task {
                            try await healthDataManager.addBloodTest(bloodTest)
                        }
                    }
                )
            }
            .sheet(item: $editingBloodTest) { bloodTest in
                BloodTestEntryView(bloodTest: bloodTest) { updated in
                    Task {
                        try await healthDataManager.updateBloodTest(updated)
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
                            try await healthDataManager.savePersonalInfo(updatedInfo)
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
                            try await healthDataManager.savePersonalInfo(updatedInfo)
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
struct DocumentsView: View {
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
    @State private var selectedDocument: MedicalDocument?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var viewMode: DocumentViewMode = .list
    @State private var showingDocumentTypeSelector = false
    @State private var pendingDocumentForCategory: MedicalDocument?
    @State private var showingImportReview = false
    @State private var activeAutoImportSummary: AutoImportSummary?
    @State private var autoImportBannerDismissTask: Task<Void, Never>?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.editMode) private var editMode

    /// When false (e.g. embedded in HealthTabView), renders content without its
    /// own NavigationStack/SplitView and uses sheet-based detail on all devices.
    var embedInNavigation: Bool = true

    private var isIPad: Bool {
        PlatformCapabilities.usesExpandedLayout(horizontalSizeClass: horizontalSizeClass)
    }

    /// The two-column split is only used when this view owns its navigation.
    private var usesSplitView: Bool {
        isIPad && embedInNavigation
    }

    private var supportsDocumentScanning: Bool {
        PlatformCapabilities.supportsDocumentScanning
    }

    var body: some View {
        Group {
            if usesSplitView {
                documentsSplitView
            } else if embedInNavigation {
                documentsStackView
            } else {
                documentsPrimaryContent
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentCameraView { scan in
                Task {
                    if let document = await documentManager.importScannedDocument(scan) {
                        pendingDocumentForCategory = document
                        selectedDocument = document
                        showingDocumentTypeSelector = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.pdf, .plainText, .image],
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
        .sheet(item: Binding(
            get: { usesSplitView ? nil : selectedDocument },
            set: { selectedDocument = $0 }
        )) { document in
            DocumentDetailView(
                document: document,
                documentManager: documentManager,
                documentProcessor: documentProcessor
            )
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
                        Task {
                            await handleImportReviewComplete(review: review, selectedGroups: selectedGroups)
                            showingImportReview = false
                        }
                    }
                )
            }
        }
        .onChange(of: documentProcessor.pendingImportReview) { oldValue, newValue in
            // Show review sheet when pending review is set
            if newValue != nil {
                showingImportReview = true
            } else {
                showingImportReview = false
            }
        }
        .onChange(of: documentProcessor.lastAutoImportSummary) { _, newValue in
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
                        }
                    }
                )
            }
        }
    }

    private var documentsStackView: some View {
        NavigationStack {
            documentsPrimaryContent
        }
    }

    private var documentsSplitView: some View {
        NavigationSplitView {
            documentsPrimaryContent
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 520)
        } detail: {
            if let selectedDocument {
                DocumentDetailView(
                    document: selectedDocument,
                    documentManager: documentManager,
                    documentProcessor: documentProcessor,
                    showsCloseButton: false
                )
            } else {
                ContentUnavailableView(
                    "Select a Document",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a document to preview details and extracted health data.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var documentsPrimaryContent: some View {
        Group {
            if documentManager.documents.isEmpty {
                DocumentsEmptyStateView(
                    supportsDocumentScanning: supportsDocumentScanning,
                    onScanDocument: showDocumentScanner,
                    onImportFile: showDocumentPicker,
                    onImportPhotos: showPhotosPicker
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
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if !documentManager.documents.isEmpty {
                        HStack {
                            EditButton()
                                .voiceOverLabel(
                                    "Edit Documents",
                                    hint: "Toggle edit mode to select documents",
                                    traits: [.button]
                                )

                            if editMode?.wrappedValue.isEditing == true && !documentManager.selectedDocuments.isEmpty {
                                Button("Batch") {
                                    showingBatchProcessing = true
                                }
                                .font(.caption)
                                .touchTarget()
                                .voiceOverLabel(
                                    "Batch Process",
                                    hint: "Process selected documents together",
                                    traits: [.button]
                                )
                            }
                        }
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !documentManager.documents.isEmpty {
                        // View mode toggle (iPad only)
                        if isIPad {
                            Picker("View Mode", selection: $viewMode) {
                                Image(systemName: "list.bullet")
                                    .accessibilityLabel("List View")
                                    .tag(DocumentViewMode.list)
                                Image(systemName: "square.grid.2x2")
                                    .accessibilityLabel("Grid View")
                                    .tag(DocumentViewMode.grid)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                            .voiceOverLabel(
                                "View Mode",
                                hint: "Switch between list and grid view",
                                traits: [.button]
                            )
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
                        Image(systemName: "plus")
                            .touchTarget()
                    }
                    .voiceOverLabel(
                        "Add Document",
                        hint: "Menu to add new documents",
                        traits: [.button]
                    )
                }
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

                // Show category selector for first document
                if let firstDoc = importedDocs.first {
                    pendingDocumentForCategory = firstDoc
                    selectedDocument = firstDoc
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
            if let firstDoc = importedDocs.first {
                pendingDocumentForCategory = firstDoc
                selectedDocument = firstDoc
                showingDocumentTypeSelector = true
            }

            selectedPhotos = []
        }
    }

    private func handleImportReviewComplete(review: PendingImportReview, selectedGroups: [BloodTestImportGroup]) async {
        AppLog.shared.ui("User completed import review for \(selectedGroups.count) groups")

        // Update the blood test result with user's selections
        var updatedBloodTest = review.bloodTestResult

        // Create a map of selected candidates by standard key
        // Only include non-nil selections (nil means ignore)
        var selectedCandidatesByKey: [String: BloodTestImportCandidate] = [:]
        for group in selectedGroups {
            if let selectedId = group.selectedCandidateId,
               let selectedCandidate = group.candidates.first(where: { $0.id == selectedId }) {
                selectedCandidatesByKey[group.standardKey] = selectedCandidate
                AppLog.shared.ui("User selected '\(selectedCandidate.originalTestName)' = \(selectedCandidate.value) for '\(group.standardTestName)'")
            } else {
                AppLog.shared.ui("User ignored group '\(group.standardTestName)'")
            }
        }

        // Reconstruct the results list based ONLY on selected candidates
        var updatedResults: [BloodTestItem] = []
        var processedKeys: Set<String> = []

        // In the new flow, we can just iterate through the selected candidates map
        // because we want to discard anything that wasn't selected.
        // However, we need to map back to BloodTestItem which needs category info.
        // The candidate doesn't have category, but the StandardizedLabParameters do.

        for (standardKey, selectedCandidate) in selectedCandidatesByKey {
             if let standardParam = BloodTestResult.standardizedLabParameters[standardKey] {

                // Check if this was an update to an existing item (preserve ID if possible? not strictly necessary)
                // or just create new items. Creating new is cleaner here since we are "Importing".

                var notes = selectedCandidate.originalTestName != standardParam.name ? "Original: \(selectedCandidate.originalTestName)" : nil
                if selectedCandidate.originalTestName.lowercased().contains("calc") {
                    notes = (notes == nil ? "" : notes! + "\n") + "Calculated"
                }

                let newItem = BloodTestItem(
                    name: standardParam.name,
                    value: selectedCandidate.value,
                    unit: selectedCandidate.unit ?? standardParam.unit,
                    referenceRange: selectedCandidate.referenceRange ?? standardParam.referenceRange,
                    isAbnormal: selectedCandidate.isAbnormal,
                    category: standardParam.category,
                    notes: notes,
                    confidence: selectedCandidate.confidence
                )
                updatedResults.append(newItem)
                processedKeys.insert(standardKey)
            }
        }

        updatedBloodTest.results = updatedResults

        // Remove pending review flag; record the audit trail of what was
        // auto-accepted vs user-reviewed
        var metadata = updatedBloodTest.metadata ?? [:]
        metadata.removeValue(forKey: "pending_review")
        metadata["import_review_completed"] = "true"
        metadata["reviewed_groups_count"] = String(selectedGroups.count)
        metadata["imported_items_count"] = String(updatedResults.count)
        metadata["auto_accepted_keys"] = selectedGroups
            .filter { $0.isAutoAccepted && $0.selectedCandidateId != nil }
            .map { $0.standardKey }.joined(separator: ",")
        metadata["reviewed_keys"] = selectedGroups
            .filter { !$0.isAutoAccepted && $0.selectedCandidateId != nil }
            .map { $0.standardKey }.joined(separator: ",")
        updatedBloodTest.metadata = metadata

        // Save the updated blood test
        do {
            let healthDataManager = HealthDataManager.shared
            try await healthDataManager.addBloodTest(updatedBloodTest)
            AppLog.shared.ui("Saved blood test after import review with \(updatedResults.count) results")

            // Clear pending review
            await MainActor.run {
                documentProcessor.pendingImportReview = nil
            }
        } catch {
            AppLog.shared.ui("Failed to save blood test after review: \(error)", level: .error)
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
                onDocumentTap: { document in
                    selectedDocument = document
                }
            )
        case .grid:
            DocumentGridView(
                documents: documentManager.filteredDocuments,
                selectedDocuments: $documentManager.selectedDocuments,
                onDocumentTap: { document in
                    selectedDocument = document
                }
            )
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
    @State private var showingConversationList = false
    @State private var searchText = ""
    @State private var selectedConversationId: UUID?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        PlatformCapabilities.usesExpandedLayout(horizontalSizeClass: horizontalSizeClass)
    }

    private var shouldUseSplitView: Bool {
        isIPad
    }

    var body: some View {
        Group {
            if shouldUseSplitView {
                iPadSplitView
            } else {
                iPhoneView
            }
        }
        .sheet(isPresented: $showingContextSelector) {
            UnifiedContextSelectorView(chatManager: chatManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await chatManager.loadConversations()
            // Skip automatic connection test on startup to avoid console noise
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)) { _ in
            // Handle keyboard appearance for iPad
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)) { _ in
            // Handle keyboard dismissal for iPad
        }
    }

    // MARK: - iPad Split View
    private var iPadSplitView: some View {
        NavigationSplitView {
            // Sidebar with conversations
            ConversationSidebarView(
                conversations: chatManager.conversations,
                selectedConversationId: $selectedConversationId,
                searchText: $searchText,
                onSelectConversation: { conversation in
                    chatManager.selectConversation(conversation)
                    selectedConversationId = conversation.id
                },
                onNewConversation: {
                    Task {
                        let conversation = try await chatManager.startNewConversation()
                        selectedConversationId = conversation.id
                    }
                },
                onDeleteConversation: { conversation in
                    Task {
                        try await chatManager.deleteConversation(conversation)
                        if selectedConversationId == conversation.id {
                            selectedConversationId = nil
                        }
                    }
                }
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 400)
        } detail: {
            // Main chat interface
            ChatDetailView(
                chatManager: chatManager,
                showingContextSelector: $showingContextSelector,
                isIPad: isIPad
            )
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone View
    private var iPhoneView: some View {
        NavigationStack {
            ChatDetailView(
                chatManager: chatManager,
                showingContextSelector: $showingContextSelector,
                isIPad: isIPad
            )
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Button("Conversations") {
                            showingConversationList = true
                        }
                        .keyboardShortcut("l", modifiers: [.command])
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("New Chat") {
                            Task {
                                _ = try await chatManager.startNewConversation()
                            }
                        }
                        .keyboardShortcut("n", modifiers: [.command])
                    }
                }
                .sheet(isPresented: $showingConversationList) {
                    ConversationListView(
                        conversations: chatManager.conversations,
                        onSelectConversation: { conversation in
                            chatManager.selectConversation(conversation)
                            showingConversationList = false
                        },
                        onDeleteConversation: { conversation in
                            Task {
                                try await chatManager.deleteConversation(conversation)
                                if chatManager.currentConversation?.id == conversation.id {
                                    chatManager.currentConversation = nil
                                }
                            }
                        }
                    )
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
