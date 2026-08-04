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

    func testOnDeviceExtractionModelSelectionRejectsTextOnlyModel() {
        let defaults = UserDefaults.standard
        let key = MLXModelInfo.SettingsKeys.selectedExtractionModelId
        let previousValue = defaults.string(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(MLXModelInfo.mediPhi4B.id, forKey: key)
        XCTAssertNil(MLXModelInfo.selectedExtractionModel)

        defaults.set(MLXModelInfo.qwen35_4B_VLM.id, forKey: key)
        XCTAssertEqual(MLXModelInfo.selectedExtractionModel, .qwen35_4B_VLM)
    }

    func testBedrockExtractionModelsOnlyIncludeVisionCapableModels() {
        XCTAssertFalse(AWSBedrockModel.visionExtractionModels.isEmpty)
        XCTAssertTrue(AWSBedrockModel.visionExtractionModels.allSatisfy { $0.supportsVisionExtraction })
        XCTAssertFalse(AWSBedrockModel.llama4Maverick.supportsVisionExtraction)
        XCTAssertFalse(AWSBedrockModel.amazonNovaPremier.supportsVisionExtraction)
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

    func testOpenAIEndpointValidatorAllowsHTTPS() {
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("https://api.example.test/v1"))
    }

    func testOpenAIEndpointValidatorAllowsLocalhostHTTP() {
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("http://localhost:4000"))
    }

    func testOpenAIEndpointValidatorAllowsIPv4LoopbackHTTP() {
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("http://127.0.0.1:4000"))
    }

    func testOpenAIEndpointValidatorAllowsIPv6LoopbackHTTP() {
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("http://[::1]:4000"))
    }

    func testOpenAIEndpointValidatorRejectsPublicHTTP() {
        XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid("http://api.example.test"))
    }

    func testOpenAIEndpointValidatorRejectsUnsupportedScheme() {
        XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid("ftp://localhost:4000"))
    }

    func testOpenAIEndpointValidatorRejectsMissingHost() {
        XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid("https:///v1"))
    }

    func testOpenAIEndpointValidatorRejectsEmbeddedCredentials() {
        XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid("https://synthetic-user:synthetic-password@example.test"))
    }

    func testInvalidOpenAIEndpointIsNotPersistedOverPriorValidEndpoint() {
        let suiteName = "SettingsManagerEndpointTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("https://api.example.test", forKey: "openAICompatibleBaseURL")
        let manager = SettingsManager(userDefaults: defaults)
        manager.openAICompatibleAPIKey = ""
        manager.openAICompatibleBaseURL = "http://public.example.test"
        manager.saveSettings()

        XCTAssertEqual(
            defaults.string(forKey: "openAICompatibleBaseURL"),
            "https://api.example.test"
        )
    }

    func testInvalidOpenAIEndpointFailsBeforeRequestConstruction() async {
        let client = OpenAICompatibleClient(baseURL: "http://public.example.test")

        do {
            _ = try await client.listModels()
            XCTFail("An invalid endpoint must fail before constructing a request")
        } catch let error as OpenAICompatibleError {
            XCTAssertEqual(error.localizedDescription, "Invalid API URL")
        } catch {
            XCTFail("Unexpected error: \(error.localizedDescription)")
        }
    }
}
