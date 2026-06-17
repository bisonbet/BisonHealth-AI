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
}
