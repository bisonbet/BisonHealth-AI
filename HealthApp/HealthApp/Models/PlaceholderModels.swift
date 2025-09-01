import Foundation

// MARK: - Imaging Report (Placeholder)
struct ImagingReport: HealthDataProtocol {
    let id: UUID
    let type: HealthDataType = .imagingReport
    
    // Placeholder properties for future implementation
    var studyDate: Date?
    var studyType: ImagingStudyType?
    var bodyPart: String?
    var findings: String?
    var impression: String?
    var radiologist: String?
    var facility: String?
    
    // Protocol Requirements
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    init(
        id: UUID = UUID(),
        studyDate: Date? = nil,
        studyType: ImagingStudyType? = nil,
        bodyPart: String? = nil,
        findings: String? = nil,
        impression: String? = nil,
        radiologist: String? = nil,
        facility: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.studyDate = studyDate
        self.studyType = studyType
        self.bodyPart = bodyPart
        self.findings = findings
        self.impression = impression
        self.radiologist = radiologist
        self.facility = facility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

// MARK: - Health Checkup (Placeholder)
struct HealthCheckup: HealthDataProtocol {
    let id: UUID
    let type: HealthDataType = .healthCheckup
    
    // Placeholder properties for future implementation
    var checkupDate: Date?
    var checkupType: CheckupType?
    var provider: String?
    var facility: String?
    var vitalSigns: VitalSigns?
    var assessments: [String]?
    var recommendations: [String]?
    var nextAppointment: Date?
    
    // Protocol Requirements
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    init(
        id: UUID = UUID(),
        checkupDate: Date? = nil,
        checkupType: CheckupType? = nil,
        provider: String? = nil,
        facility: String? = nil,
        vitalSigns: VitalSigns? = nil,
        assessments: [String]? = nil,
        recommendations: [String]? = nil,
        nextAppointment: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.checkupDate = checkupDate
        self.checkupType = checkupType
        self.provider = provider
        self.facility = facility
        self.vitalSigns = vitalSigns
        self.assessments = assessments
        self.recommendations = recommendations
        self.nextAppointment = nextAppointment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

// MARK: - Supporting Enums and Structures

enum ImagingStudyType: String, CaseIterable, Codable {
    case xray = "xray"
    case ct = "ct"
    case mri = "mri"
    case ultrasound = "ultrasound"
    case mammography = "mammography"
    case dexa = "dexa"
    case nuclear = "nuclear"
    case pet = "pet"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .xray:
            return "X-Ray"
        case .ct:
            return "CT Scan"
        case .mri:
            return "MRI"
        case .ultrasound:
            return "Ultrasound"
        case .mammography:
            return "Mammography"
        case .dexa:
            return "DEXA Scan"
        case .nuclear:
            return "Nuclear Medicine"
        case .pet:
            return "PET Scan"
        case .other:
            return "Other"
        }
    }
}

enum CheckupType: String, CaseIterable, Codable {
    case annual = "annual"
    case physical = "physical"
    case wellness = "wellness"
    case followUp = "follow_up"
    case specialist = "specialist"
    case preventive = "preventive"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .annual:
            return "Annual Checkup"
        case .physical:
            return "Physical Exam"
        case .wellness:
            return "Wellness Visit"
        case .followUp:
            return "Follow-up Visit"
        case .specialist:
            return "Specialist Consultation"
        case .preventive:
            return "Preventive Care"
        case .other:
            return "Other"
        }
    }
}

struct VitalSigns: Codable {
    var bloodPressureSystolic: Int?
    var bloodPressureDiastolic: Int?
    var heartRate: Int?
    var temperature: Measurement<UnitTemperature>?
    var respiratoryRate: Int?
    var oxygenSaturation: Double?
    var height: Measurement<UnitLength>?
    var weight: Measurement<UnitMass>?
    var bmi: Double?
    
    init(
        bloodPressureSystolic: Int? = nil,
        bloodPressureDiastolic: Int? = nil,
        heartRate: Int? = nil,
        temperature: Measurement<UnitTemperature>? = nil,
        respiratoryRate: Int? = nil,
        oxygenSaturation: Double? = nil,
        height: Measurement<UnitLength>? = nil,
        weight: Measurement<UnitMass>? = nil,
        bmi: Double? = nil
    ) {
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.heartRate = heartRate
        self.temperature = temperature
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.height = height
        self.weight = weight
        self.bmi = bmi
    }
    
    var bloodPressureString: String? {
        guard let systolic = bloodPressureSystolic,
              let diastolic = bloodPressureDiastolic else {
            return nil
        }
        return "\(systolic)/\(diastolic) mmHg"
    }
}

// MARK: - Validation Extensions
extension ImagingReport {
    var isValid: Bool {
        return studyDate != nil && studyType != nil
    }
}

extension HealthCheckup {
    var isValid: Bool {
        return checkupDate != nil && checkupType != nil
    }
}