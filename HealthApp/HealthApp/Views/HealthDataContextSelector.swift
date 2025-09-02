import SwiftUI

struct HealthDataContextSelector: View {
    @Binding var selectedTypes: Set<HealthDataType>
    let onSave: (Set<HealthDataType>) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var localSelection: Set<HealthDataType>
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    init(selectedTypes: Binding<Set<HealthDataType>>, onSave: @escaping (Set<HealthDataType>) -> Void) {
        self._selectedTypes = selectedTypes
        self.onSave = onSave
        self._localSelection = State(initialValue: selectedTypes.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            if isIPad {
                // iPad optimized layout with larger cards
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(HealthDataType.allCases, id: \.self) { dataType in
                            HealthDataTypeCard(
                                dataType: dataType,
                                isSelected: localSelection.contains(dataType),
                                onToggle: {
                                    if localSelection.contains(dataType) {
                                        localSelection.remove(dataType)
                                    } else {
                                        localSelection.insert(dataType)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    if !localSelection.isEmpty {
                        ContextSizeIndicator(selectedTypes: localSelection)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                    }
                }
                .navigationTitle("Health Data Context")
                .navigationBarTitleDisplayMode(.large)
            } else {
                // iPhone layout with list
                List {
                    Section {
                        Text("Select which health data types to include in your AI conversations. This helps provide more relevant and personalized responses.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Section("Available Data Types") {
                        ForEach(HealthDataType.allCases, id: \.self) { dataType in
                            HealthDataTypeRow(
                                dataType: dataType,
                                isSelected: localSelection.contains(dataType),
                                onToggle: {
                                    if localSelection.contains(dataType) {
                                        localSelection.remove(dataType)
                                    } else {
                                        localSelection.insert(dataType)
                                    }
                                }
                            )
                        }
                    }
                    
                    if !localSelection.isEmpty {
                        Section("Context Size") {
                            ContextSizeIndicator(selectedTypes: localSelection)
                        }
                    }
                }
                .navigationTitle("Health Data Context")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    selectedTypes = localSelection
                    onSave(localSelection)
                    dismiss()
                }
                .fontWeight(.semibold)
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
    }
}

struct HealthDataTypeRow: View {
    let dataType: HealthDataType
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: dataType.icon)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(dataType.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(dataTypeDescription(for: dataType))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func dataTypeDescription(for type: HealthDataType) -> String {
        switch type {
        case .personalInfo:
            return "Basic demographics, allergies, medications"
        case .bloodTest:
            return "Lab results and blood work"
        case .imagingReport:
            return "X-rays, MRIs, CT scans"
        case .healthCheckup:
            return "Physical exams and checkups"
        }
    }
}

struct HealthDataTypeCard: View {
    let dataType: HealthDataType
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: dataType.icon)
                        .font(.system(size: 32))
                        .foregroundColor(isSelected ? .white : .blue)
                    
                    Text(dataType.displayName)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)
                        .multilineTextAlignment(.center)
                }
                
                Text(dataTypeDescription(for: dataType))
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                HStack {
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .white : .secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private func dataTypeDescription(for type: HealthDataType) -> String {
        switch type {
        case .personalInfo:
            return "Basic demographics, allergies, medications, and medical history"
        case .bloodTest:
            return "Lab results, blood work, and biomarker data"
        case .imagingReport:
            return "X-rays, MRIs, CT scans, and radiology reports"
        case .healthCheckup:
            return "Physical exams, routine checkups, and wellness visits"
        }
    }
}

struct ContextSizeIndicator: View {
    let selectedTypes: Set<HealthDataType>
    
    private var estimatedSize: ContextSize {
        switch selectedTypes.count {
        case 0:
            return .none
        case 1:
            return .small
        case 2:
            return .medium
        case 3:
            return .large
        default:
            return .extraLarge
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                
                Text("Context Size Estimate")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            HStack {
                Text(estimatedSize.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(estimatedSize.color)
                
                Spacer()
                
                Text(estimatedSize.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: estimatedSize.progressValue)
                .progressViewStyle(LinearProgressViewStyle(tint: estimatedSize.color))
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

enum ContextSize {
    case none
    case small
    case medium
    case large
    case extraLarge
    
    var displayName: String {
        switch self {
        case .none:
            return "No Context"
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        case .extraLarge:
            return "Extra Large"
        }
    }
    
    var description: String {
        switch self {
        case .none:
            return "No health data will be included"
        case .small:
            return "Minimal context, fast responses"
        case .medium:
            return "Good balance of detail and performance"
        case .large:
            return "Comprehensive context, slower responses"
        case .extraLarge:
            return "Maximum detail, may impact performance"
        }
    }
    
    var color: Color {
        switch self {
        case .none:
            return .gray
        case .small:
            return .green
        case .medium:
            return .blue
        case .large:
            return .orange
        case .extraLarge:
            return .red
        }
    }
    
    var progressValue: Double {
        switch self {
        case .none:
            return 0.0
        case .small:
            return 0.25
        case .medium:
            return 0.5
        case .large:
            return 0.75
        case .extraLarge:
            return 1.0
        }
    }
}

#Preview {
    HealthDataContextSelector(
        selectedTypes: .constant([.personalInfo, .bloodTest]),
        onSave: { _ in }
    )
}