import SwiftUI

struct BloodTestsSection: View {
    let bloodTests: [BloodTestResult]
    let onAddNew: () -> Void
    
    var body: some View {
        Section {
            if bloodTests.isEmpty {
                EmptyBloodTestsView()
            } else {
                ForEach(bloodTests.prefix(3)) { bloodTest in
                    BloodTestRowView(bloodTest: bloodTest)
                }
                
                if bloodTests.count > 3 {
                    NavigationLink("View All (\(bloodTests.count))") {
                        BloodTestListView(bloodTests: bloodTests)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        } header: {
            HStack {
                Label("Blood Test Results", systemImage: "drop.fill")
                Spacer()
                Button("Add") {
                    onAddNew()
                }
                .font(.caption)
            }
        }
    }
}

struct BloodTestRowView: View {
    let bloodTest: BloodTestResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateFormatter.mediumDate.string(from: bloodTest.testDate))
                        .font(.headline)
                    
                    if let lab = bloodTest.laboratoryName {
                        Text(lab)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(bloodTest.results.count) tests")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !bloodTest.abnormalResults.isEmpty {
                        Text("\(bloodTest.abnormalResults.count) abnormal")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !bloodTest.abnormalResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bloodTest.abnormalResults.prefix(3)) { result in
                            AbnormalResultChip(result: result)
                        }
                        
                        if bloodTest.abnormalResults.count > 3 {
                            Text("+\(bloodTest.abnormalResults.count - 3) more")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AbnormalResultChip: View {
    let result: BloodTestItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.name)
                .font(.caption2)
                .fontWeight(.medium)
            
            HStack(spacing: 2) {
                Text(result.value)
                    .font(.caption2)
                    .fontWeight(.bold)
                
                if let unit = result.unit {
                    Text(unit)
                        .font(.caption2)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(6)
    }
}

struct EmptyBloodTestsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No blood test results")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Tap Add to record your blood test results")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct BloodTestListView: View {
    let bloodTests: [BloodTestResult]
    
    var body: some View {
        List(bloodTests) { bloodTest in
            NavigationLink {
                BloodTestDetailView(bloodTest: bloodTest)
            } label: {
                BloodTestRowView(bloodTest: bloodTest)
            }
        }
        .navigationTitle("Blood Test Results")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BloodTestDetailView: View {
    let bloodTest: BloodTestResult
    
    var body: some View {
        List {
            Section("Test Information") {
                InfoRow(
                    label: "Test Date",
                    value: DateFormatter.mediumDate.string(from: bloodTest.testDate),
                    icon: "calendar"
                )
                
                if let lab = bloodTest.laboratoryName {
                    InfoRow(label: "Laboratory", value: lab, icon: "building.2")
                }
                
                if let physician = bloodTest.orderingPhysician {
                    InfoRow(label: "Ordering Physician", value: physician, icon: "stethoscope")
                }
            }
            
            Section("Results") {
                ForEach(bloodTest.results) { result in
                    BloodTestItemRow(item: result)
                }
            }
        }
        .navigationTitle("Blood Test Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BloodTestItemRow: View {
    let item: BloodTestItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.headline)
                
                Spacer()
                
                if item.isAbnormal {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            HStack {
                Text(item.value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(item.isAbnormal ? .red : .primary)
                
                if let unit = item.unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if let referenceRange = item.referenceRange {
                Text("Reference: \(referenceRange)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = item.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        List {
            BloodTestsSection(
                bloodTests: [
                    BloodTestResult(
                        testDate: Date(),
                        laboratoryName: "LabCorp",
                        results: [
                            BloodTestItem(name: "Glucose", value: "110", unit: "mg/dL", referenceRange: "70-100", isAbnormal: true),
                            BloodTestItem(name: "Cholesterol", value: "180", unit: "mg/dL", referenceRange: "<200")
                        ]
                    )
                ],
                onAddNew: {}
            )
            
            BloodTestsSection(
                bloodTests: [],
                onAddNew: {}
            )
        }
    }
}