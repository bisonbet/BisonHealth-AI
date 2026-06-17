import XCTest
@testable import HealthApp

@MainActor
final class ServiceClientTests: XCTestCase {

    func testProviderConnectionStatusDisplayNames() {
        XCTAssertEqual(ProviderConnectionStatus.disconnected.displayName, "Disconnected")
        XCTAssertEqual(ProviderConnectionStatus.connecting.displayName, "Connecting...")
        XCTAssertEqual(ProviderConnectionStatus.connected.displayName, "Connected")

        XCTAssertEqual(ProviderConnectionStatus.disconnected.icon, "wifi.slash")
        XCTAssertEqual(ProviderConnectionStatus.connecting.icon, "wifi.exclamationmark")
        XCTAssertEqual(ProviderConnectionStatus.connected.icon, "wifi")
    }

    func testAIProviderConfigInitialization() {
        let config = AIProviderConfig(
            hostname: "api.example.test",
            port: 443,
            apiKey: "test-key",
            model: "test-model",
            timeout: 60,
            maxRetries: 2
        )

        XCTAssertEqual(config.hostname, "api.example.test")
        XCTAssertEqual(config.port, 443)
        XCTAssertEqual(config.apiKey, "test-key")
        XCTAssertEqual(config.model, "test-model")
        XCTAssertEqual(config.timeout, 60)
        XCTAssertEqual(config.maxRetries, 2)
    }

    func testAIProviderFactoryCreatesSupportedProviders() {
        let config = AIProviderConfig(hostname: "localhost", port: 4000, apiKey: "test-key")

        let openAIProvider = AIProviderFactory.createProvider(type: .openai, config: config)
        XCTAssertTrue(openAIProvider is OpenAIProvider)

        let anthropicProvider = AIProviderFactory.createProvider(type: .anthropic, config: config)
        XCTAssertTrue(anthropicProvider is AnthropicProvider)
    }
}
