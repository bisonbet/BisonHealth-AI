import XCTest
@testable import HealthApp

@MainActor
final class SettingsManagerTests: XCTestCase {

    private var settingsManager: SettingsManager!

    override func setUp() async throws {
        try await super.setUp()
        settingsManager = SettingsManager()
    }

    override func tearDown() async throws {
        settingsManager = nil
        try await super.tearDown()
    }

    func testDefaultServerConfigurations() {
        XCTAssertEqual(settingsManager.openAICompatibleBaseURL, "http://localhost:4000")
    }

    func testDefaultModelPreferencesUseOnDeviceProvider() {
        XCTAssertEqual(settingsManager.modelPreferences.aiProvider, .onDeviceLLM)
        XCTAssertEqual(settingsManager.modelPreferences.extractionProvider, .onDeviceLLM)
        XCTAssertEqual(settingsManager.modelPreferences.bedrockModel, AWSBedrockModel.claudeSonnet45.rawValue)
    }

    func testAIProviderDecodesUnknownProviderAsOnDevice() throws {
        let data = #""removed_provider""#.data(using: .utf8)!
        let provider = try JSONDecoder().decode(AIProvider.self, from: data)

        XCTAssertEqual(provider, .onDeviceLLM)
    }

    func testServerConfigurationValidation() {
        XCTAssertNil(settingsManager.validateServerConfiguration(ServerConfiguration(hostname: "localhost", port: 5001)))
        XCTAssertEqual(
            settingsManager.validateServerConfiguration(ServerConfiguration(hostname: "", port: 5001)),
            "Hostname cannot be empty"
        )
        XCTAssertEqual(
            settingsManager.validateServerConfiguration(ServerConfiguration(hostname: "localhost", port: 0)),
            "Port must be between 1 and 65535"
        )
    }
}
