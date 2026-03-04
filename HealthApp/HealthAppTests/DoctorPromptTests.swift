import XCTest
@testable import HealthApp

final class DoctorPromptTests: XCTestCase {

    func testCompactPromptsEnforceClinicalPersonaRules() {
        let doctors = Doctor.defaultDoctors
        XCTAssertFalse(doctors.isEmpty)

        for doctor in doctors {
            let prompt = doctor.compactSystemPrompt
            XCTAssertTrue(prompt.contains("Never say you are an AI"), "Missing anti-meta rule for \(doctor.name)")
            XCTAssertTrue(prompt.contains("If asked for your opinion"), "Missing opinion handling rule for \(doctor.name)")
            XCTAssertTrue(prompt.contains("Do not add unsolicited disclaimers"), "Missing disclaimer suppression for \(doctor.name)")
            XCTAssertTrue(prompt.contains("Role:"), "Missing explicit role section for \(doctor.name)")
        }
    }
}
