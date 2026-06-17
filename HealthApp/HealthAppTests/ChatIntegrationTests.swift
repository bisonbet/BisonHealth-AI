import XCTest
@testable import HealthApp

@MainActor
final class ChatIntegrationTests: XCTestCase {

    func testSupportedAIProvidersExcludeRemovedLocalServerProvider() {
        XCTAssertEqual(
            Set(AIProvider.allCases),
            Set([.bedrock, .openAICompatible, .onDeviceLLM])
        )
    }

    func testModelPreferencesRoundTrip() throws {
        var preferences = ModelPreferences()
        preferences.aiProvider = .openAICompatible
        preferences.openAICompatibleModel = "gpt-4o-mini"
        preferences.extractionProvider = .bedrock
        preferences.extractionBedrockModel = AWSBedrockModel.claudeSonnet45.rawValue

        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(ModelPreferences.self, from: encoded)

        XCTAssertEqual(decoded.aiProvider, .openAICompatible)
        XCTAssertEqual(decoded.openAICompatibleModel, "gpt-4o-mini")
        XCTAssertEqual(decoded.extractionProvider, .bedrock)
        XCTAssertEqual(decoded.extractionBedrockModel, AWSBedrockModel.claudeSonnet45.rawValue)
    }
}
