import XCTest
@testable import HealthApp

final class DoctorPromptTests: XCTestCase {

    func testCompactPromptsEnforceClinicalPersonaRules() {
        let doctors = Doctor.defaultDoctors
        XCTAssertFalse(doctors.isEmpty)

        for doctor in doctors {
            let prompt = doctor.compactSystemPrompt
            XCTAssertFalse(prompt.isEmpty, "Missing compact prompt for \(doctor.name)")
            XCTAssertTrue(prompt.contains("context"), "Missing context handling instruction for \(doctor.name)")
            XCTAssertTrue(prompt.contains("natural language"), "Missing response format instruction for \(doctor.name)")
        }
    }

    func testGeneticSpecialistPromptKeepsMedicationQuestionsReportGrounded() throws {
        let doctor = try XCTUnwrap(Doctor.defaultDoctors.first { $0.name == "Genetic Specialist" })

        XCTAssertTrue(doctor.systemPrompt.contains("genetic_profile"))
        XCTAssertTrue(doctor.systemPrompt.contains("Never invent"))
        XCTAssertTrue(doctor.systemPrompt.contains("start, stop, substitute, or change"))
        XCTAssertTrue(doctor.compactSystemPrompt.contains("current labeling/guidelines"))
    }
}
