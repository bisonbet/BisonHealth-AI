import XCTest
import Security
@testable import HealthApp

/// Keychain stand-in so tests never touch the test host's real keychain.
final class InMemoryKeychain: KeychainStoring {
    private var items: [String: Data] = [:]
    var storeError: Error?

    func store(data: Data, for account: String) throws {
        if let storeError { throw storeError }
        items[account] = data
    }

    func retrieve(for account: String) throws -> Data? {
        items[account]
    }

    func delete(for account: String) throws {
        items.removeValue(forKey: account)
    }

    func store(string: String, for account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try store(data: data, for: account)
    }

    func retrieveString(for account: String) throws -> String? {
        guard let data = try retrieve(for: account) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }
}

@MainActor
final class SettingsManagerTests: XCTestCase {

    private var settingsManager: SettingsManager!
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() async throws {
        try await super.setUp()
        // An isolated suite and an in-memory keychain: SettingsManager persists a real
        // API key, so the default dependencies would mutate the test host's own storage.
        suiteName = "SettingsManagerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settingsManager = SettingsManager(userDefaults: defaults, keychain: InMemoryKeychain())
    }

    override func tearDown() async throws {
        settingsManager = nil
        if !suiteName.isEmpty {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = .standard
        suiteName = ""
        try await super.tearDown()
    }

    private func makeIsolatedManager(
        _ configure: (UserDefaults) -> Void = { _ in }
    ) -> (SettingsManager, UserDefaults, InMemoryKeychain) {
        let name = "SettingsManagerTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: name) else {
            fatalError("Unable to create an isolated UserDefaults suite")
        }
        addTeardownBlock { isolatedDefaults.removePersistentDomain(forName: name) }

        configure(isolatedDefaults)
        let keychain = InMemoryKeychain()
        return (SettingsManager(userDefaults: isolatedDefaults, keychain: keychain), isolatedDefaults, keychain)
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

    func testOpenAIEndpointValidatorAllowsPrivateNetworkHTTP() {
        // Self-hosted inference servers normally run on the LAN over plain HTTP.
        let allowed = [
            "http://192.168.1.10:11434",     // RFC 1918
            "http://10.0.0.5:8000",          // RFC 1918
            "http://172.16.4.4:1234",        // RFC 1918 lower bound
            "http://172.31.255.254:1234",    // RFC 1918 upper bound
            "http://169.254.10.10:8080",     // link-local
            "http://[fd00::1]:8000",         // IPv6 unique local
            "http://[fe80::1]:8000",         // IPv6 link-local
            "http://ollama.local:11434",     // mDNS
            "http://nas.home.arpa:8000",     // RFC 8375
            "http://ollama-box:11434",       // unqualified single-label name
            "http://127.0.0.1:4000",
            "http://localhost:4000"
        ]

        for endpoint in allowed {
            XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid(endpoint), "Should allow \(endpoint)")
        }
    }

    func testOpenAIEndpointValidatorStillRejectsRoutableHTTP() {
        // Addresses adjacent to the private ranges must not be treated as local.
        let rejected = [
            "http://172.15.0.1:1234",        // just below 172.16.0.0/12
            "http://172.32.0.1:1234",        // just above 172.31.255.255
            "http://192.169.1.1:1234",       // not 192.168/16
            "http://11.0.0.1:1234",          // not 10/8
            "http://8.8.8.8:1234",
            "http://[2001:4860:4860::8888]:8000",
            "http://api.example.test",
            "http://evil.example.com.local.attacker.test"
        ]

        for endpoint in rejected {
            XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid(endpoint), "Should reject \(endpoint)")
        }
    }

    func testOpenAIEndpointValidatorTreatsIPv4MappedIPv6ByItsIPv4Value() {
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("http://[::ffff:192.168.1.10]:8000"))
        XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid("http://[::ffff:8.8.8.8]:8000"))
    }

    func testOpenAIEndpointValidatorAlwaysAllowsHTTPSForPublicHosts() {
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("https://api.example.test/v1"))
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("https://192.168.1.10:8443"))
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

    func testRejectedOpenAIEndpointIsRetainedRatherThanDiscarded() {
        // A rejected endpoint must survive a round trip so the user can see and correct
        // it. Safety comes from refusing to *use* it, not from deleting it.
        let (manager, defaults, keychain) = makeIsolatedManager {
            $0.set("http://lan-box.example.test:1234", forKey: "openAICompatibleBaseURL")
        }

        XCTAssertEqual(manager.openAICompatibleBaseURL, "http://lan-box.example.test:1234")
        XCTAssertFalse(manager.hasValidOpenAICompatibleConfig())

        manager.saveSettings()
        XCTAssertEqual(
            defaults.string(forKey: "openAICompatibleBaseURL"),
            "http://lan-box.example.test:1234"
        )

        let reloaded = SettingsManager(userDefaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.openAICompatibleBaseURL, "http://lan-box.example.test:1234")
    }

    func testLegacyPlaintextAPIKeyIsMigratedToKeychainAndRemoved() {
        let (manager, defaults, keychain) = makeIsolatedManager {
            $0.set("synthetic-legacy-api-key", forKey: "openAICompatibleAPIKey")
        }

        XCTAssertEqual(manager.openAICompatibleAPIKey, "synthetic-legacy-api-key")
        XCTAssertEqual(
            try? keychain.retrieveString(for: "settings.openAICompatible.apiKey.v1"),
            "synthetic-legacy-api-key"
        )
        XCTAssertNil(defaults.string(forKey: "openAICompatibleAPIKey"))
    }

    func testLegacyPlaintextAPIKeyIsRetainedWhenKeychainWriteFails() {
        let name = "SettingsManagerTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: name) else {
            XCTFail("Unable to create an isolated UserDefaults suite")
            return
        }
        addTeardownBlock { isolatedDefaults.removePersistentDomain(forName: name) }
        isolatedDefaults.set("synthetic-legacy-api-key", forKey: "openAICompatibleAPIKey")

        let keychain = InMemoryKeychain()
        keychain.storeError = KeychainError.storeFailed(errSecIO)
        let manager = SettingsManager(userDefaults: isolatedDefaults, keychain: keychain)

        // Losing the key outright is worse than leaving the plaintext copy in place.
        XCTAssertEqual(manager.openAICompatibleAPIKey, "synthetic-legacy-api-key")
        XCTAssertEqual(isolatedDefaults.string(forKey: "openAICompatibleAPIKey"), "synthetic-legacy-api-key")
    }

    func testClearingAPIKeyRemovesBothTheKeychainAndLegacyCopies() {
        let (manager, defaults, keychain) = makeIsolatedManager {
            $0.set("synthetic-legacy-api-key", forKey: "openAICompatibleAPIKey")
        }

        manager.openAICompatibleAPIKey = ""
        manager.saveSettings()

        XCTAssertNil(try? keychain.retrieveString(for: "settings.openAICompatible.apiKey.v1"))
        XCTAssertNil(defaults.string(forKey: "openAICompatibleAPIKey"))

        // The legacy fallback must not resurrect the cleared key on the next launch.
        let reloaded = SettingsManager(userDefaults: defaults, keychain: keychain)
        XCTAssertTrue(reloaded.openAICompatibleAPIKey.isEmpty)
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
