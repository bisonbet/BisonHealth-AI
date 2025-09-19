import Foundation

// MARK: - Blood Test Data Manager
class BloodTestDataManager: ObservableObject {

    // MARK: - Singleton
    static let shared = BloodTestDataManager()

    // MARK: - Published Properties
    @Published var commonLaboratories: [String] = []
    @Published var commonPhysicians: [String] = []
    @Published var recentLaboratories: [String] = []
    @Published var recentPhysicians: [String] = []

    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let maxRecentItems = 10

    // Keys for UserDefaults
    private enum Keys {
        static let recentLaboratories = "recentLaboratories"
        static let recentPhysicians = "recentPhysicians"
        static let commonLaboratories = "commonLaboratories"
        static let commonPhysicians = "commonPhysicians"
    }

    // MARK: - Initialization
    private init() {
        loadStoredData()
        setupDefaultData()
    }

    // MARK: - Laboratory Management
    func addLaboratory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add to recent list
        var recent = recentLaboratories
        recent.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recent.insert(trimmed, at: 0)
        if recent.count > maxRecentItems {
            recent = Array(recent.prefix(maxRecentItems))
        }

        recentLaboratories = recent
        saveRecentLaboratories()
    }

    func getAllLaboratories() -> [String] {
        var all = Set<String>()
        all.formUnion(commonLaboratories)
        all.formUnion(recentLaboratories)
        return Array(all).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Physician Management
    func addPhysician(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add to recent list
        var recent = recentPhysicians
        recent.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recent.insert(trimmed, at: 0)
        if recent.count > maxRecentItems {
            recent = Array(recent.prefix(maxRecentItems))
        }

        recentPhysicians = recent
        saveRecentPhysicians()
    }

    func getAllPhysicians() -> [String] {
        var all = Set<String>()
        all.formUnion(commonPhysicians)
        all.formUnion(recentPhysicians)
        return Array(all).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Test Types
    func getStandardizedTestTypes() -> [BloodTestTypeOption] {
        let parameters = BloodTestResult.standardizedLabParameters

        // Group by category and create options
        var categorizedTests: [BloodTestCategory: [BloodTestTypeOption]] = [:]

        for (_, parameter) in parameters {
            let option = BloodTestTypeOption(
                key: parameter.key,
                displayName: parameter.name,
                unit: parameter.unit,
                referenceRange: parameter.referenceRange,
                category: parameter.category,
                description: parameter.description
            )

            if categorizedTests[parameter.category] == nil {
                categorizedTests[parameter.category] = []
            }
            categorizedTests[parameter.category]?.append(option)
        }

        // Sort within categories and flatten
        var allTests: [BloodTestTypeOption] = []
        let sortedCategories = BloodTestCategory.allCases.sorted { $0.displayName < $1.displayName }

        for category in sortedCategories {
            if let tests = categorizedTests[category] {
                let sortedTests = tests.sorted { $0.displayName < $1.displayName }
                allTests.append(contentsOf: sortedTests)
            }
        }

        return allTests
    }

    func getTestTypesByCategory() -> [BloodTestCategory: [BloodTestTypeOption]] {
        let allTests = getStandardizedTestTypes()
        return Dictionary(grouping: allTests) { $0.category }
    }

    // MARK: - Common Units
    func getCommonUnits() -> [String] {
        return [
            "mg/dL",
            "g/dL",
            "mmol/L",
            "mEq/L",
            "IU/L",
            "U/L",
            "ng/mL",
            "pg/mL",
            "μg/dL",
            "ng/dL",
            "μIU/mL",
            "mIU/L",
            "mg/L",
            "mOsm/kg",
            "µmol/L",
            "nmol/L",
            "µg/L",
            "µg/mL",
            "µg/mL FEU",
            "IU/mL",
            "K/uL",
            "M/uL",
            "%",
            "fL",
            "pg",
            "sec",
            "mm/hr",
            "mL/min/1.73m²"
        ].sorted()
    }

    func getUnitsForTestType(_ testKey: String) -> [String] {
        guard let parameter = BloodTestResult.standardizedLabParameters[testKey] else {
            return getCommonUnits()
        }

        var units = getCommonUnits()
        if let preferredUnit = parameter.unit, !units.contains(preferredUnit) {
            units.insert(preferredUnit, at: 0)
        }

        return units
    }

    // MARK: - Search Functions
    func searchTestTypes(_ query: String) -> [BloodTestTypeOption] {
        let allTests = getStandardizedTestTypes()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allTests
        }

        let lowercaseQuery = query.lowercased()
        return allTests.filter { test in
            test.displayName.lowercased().contains(lowercaseQuery) ||
            test.key.lowercased().contains(lowercaseQuery) ||
            test.description?.lowercased().contains(lowercaseQuery) == true
        }
    }

    // MARK: - Data Persistence
    private func loadStoredData() {
        recentLaboratories = userDefaults.stringArray(forKey: Keys.recentLaboratories) ?? []
        recentPhysicians = userDefaults.stringArray(forKey: Keys.recentPhysicians) ?? []
        commonLaboratories = userDefaults.stringArray(forKey: Keys.commonLaboratories) ?? []
        commonPhysicians = userDefaults.stringArray(forKey: Keys.commonPhysicians) ?? []
    }

    private func saveRecentLaboratories() {
        userDefaults.set(recentLaboratories, forKey: Keys.recentLaboratories)
    }

    private func saveRecentPhysicians() {
        userDefaults.set(recentPhysicians, forKey: Keys.recentPhysicians)
    }

    private func setupDefaultData() {
        if commonLaboratories.isEmpty {
            commonLaboratories = [
                "LabCorp",
                "Quest Diagnostics",
                "Mayo Clinic Laboratories",
                "Cleveland Clinic",
                "Kaiser Permanente Lab",
                "ARUP Laboratories",
                "BioReference Laboratories",
                "Sonic Healthcare",
                "Laboratory Medicine Associates",
                "Regional Medical Center Lab"
            ]
            userDefaults.set(commonLaboratories, forKey: Keys.commonLaboratories)
        }

        if commonPhysicians.isEmpty {
            commonPhysicians = [
                "Dr. Smith",
                "Dr. Johnson",
                "Dr. Williams",
                "Dr. Brown",
                "Dr. Davis",
                "Dr. Miller",
                "Dr. Wilson",
                "Dr. Garcia",
                "Dr. Rodriguez",
                "Dr. Lee"
            ]
            userDefaults.set(commonPhysicians, forKey: Keys.commonPhysicians)
        }
    }
}

// MARK: - Supporting Data Structures

struct BloodTestTypeOption: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let displayName: String
    let unit: String?
    let referenceRange: String?
    let category: BloodTestCategory
    let description: String?

    var categoryDisplayName: String {
        category.displayName
    }

    var fullDisplayName: String {
        if let unit = unit {
            return "\(displayName) (\(unit))"
        }
        return displayName
    }
}

// MARK: - Extensions

extension BloodTestCategory {
    static var allCasesOrdered: [BloodTestCategory] {
        return [
            .completeBloodCount,
            .basicMetabolicPanel,
            .comprehensiveMetabolicPanel,
            .lipidPanel,
            .liverFunction,
            .kidneyFunction,
            .thyroidFunction,
            .diabetesMarkers,
            .cardiacMarkers,
            .inflammatoryMarkers,
            .vitaminsAndMinerals,
            .hormones,
            .immunology,
            .coagulation,
            .other
        ]
    }
}