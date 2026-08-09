import XCTest
import Security
@testable import HealthApp

/// Keychain stand-in so tests never touch the test host's real keychain.
final class InMemoryKeychain: KeychainStoring {
    private var items: [String: Data] = [:]
    var storeError: Error?
    var deleteError: Error?
    var retrieveError: Error?

    /// Reads the backing store directly, bypassing `retrieveError`, so a test can assert
    /// what actually survived a simulated read failure.
    func storedValue(for account: String) -> String? {
        items[account].flatMap { String(data: $0, encoding: .utf8) }
    }

    func store(data: Data, for account: String) throws {
        if let storeError { throw storeError }
        items[account] = data
    }

    func retrieve(for account: String) throws -> Data? {
        if let retrieveError { throw retrieveError }
        return items[account]
    }

    func delete(for account: String) throws {
        if let deleteError { throw deleteError }
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

    func testOpenAIEndpointValidatorRejectsNoncanonicalPublicIPv4LiteralsOverHTTP() {
        // Resolvers accept whole-integer, hex, octal and shortened IPv4 spellings. Each
        // of these denotes a routable address, so none may be taken for a LAN host.
        // 010.010.010.010 is the sharp case: strict parsing reads it as private
        // 10.10.10.10 while the resolver reads it as 8.8.8.8.
        let rejected = [
            "http://134744072",          // decimal 8.8.8.8
            "http://0x8080808",          // hex 8.8.8.8
            "http://010.010.010.010",    // 10.10.10.10 strictly, 8.8.8.8 to a resolver
            "http://8.8.8",              // shortened 8.8.0.8
            "http://0177.0.0.1"          // 177.0.0.1 strictly, 127.0.0.1 to a resolver
        ]
        for endpoint in rejected {
            XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid(endpoint), "Should reject \(endpoint)")
        }

        // A numeric spelling of a genuinely private address stays allowed: the rule is
        // about where the request goes, not how the user typed it.
        let allowed = [
            "http://3232235777",         // decimal 192.168.1.1
            "http://2130706433"          // decimal 127.0.0.1
        ]
        for endpoint in allowed {
            XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid(endpoint), "Should allow \(endpoint)")
        }
    }

    func testOpenAIEndpointValidatorStillAcceptsRealHostNames() {
        // The numeric checks must not swallow ordinary single-label LAN names.
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("http://ollama-box"))
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("http://nas"))
    }

    func testOpenAIEndpointValidatorDoesNotTruncatePublicHostsAtAPercentSign() {
        // URLComponents decodes the host, so "nas%25.evil.example.test" arrives as
        // "nas%.evil.example.test". Treating that percent sign as an IPv6 zone ID would
        // truncate it to the LAN-looking label "nas" and permit cleartext to a public
        // domain. Zone IDs belong to IPv6 literals only.
        XCTAssertFalse(OpenAICompatibleEndpointValidator.isValid("http://nas%25.evil.example.test/v1"))
        XCTAssertFalse(OpenAICompatibleEndpointValidator.isPrivateNetworkHost("nas%.evil.example.test"))

        // A genuine IPv6 zone ID is still handled.
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isValid("http://[fe80::1%25en0]:8000"))
        XCTAssertTrue(OpenAICompatibleEndpointValidator.isPrivateNetworkHost("fe80::1%en0"))
    }

    func testOpenAIEndpointValidatorRejectsPublicHostsThatMerelyContainLocalSuffixes() {
        let rejected = [
            "http://foo.local.evil.example.test",   // ".local" is not the suffix
            "http://example.milan",                 // ends in "lan" but not ".lan"
            "http://internal.example.test"
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

    func testUnreadableKeychainKeyIsNotOverwrittenByTheLegacyCopy() {
        let name = "SettingsManagerTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: name) else {
            XCTFail("Unable to create an isolated UserDefaults suite")
            return
        }
        addTeardownBlock { isolatedDefaults.removePersistentDomain(forName: name) }
        isolatedDefaults.set("synthetic-stale-legacy-key", forKey: "openAICompatibleAPIKey")

        let keychain = InMemoryKeychain()
        try? keychain.store(string: "synthetic-current-key", for: "settings.openAICompatible.apiKey.v1")
        keychain.retrieveError = KeychainError.retrieveFailed(errSecIO)

        let manager = SettingsManager(userDefaults: isolatedDefaults, keychain: keychain)

        // A read failure is not an absent key: the good secure value must survive, and
        // the stale plaintext one must not be written over it.
        XCTAssertNotNil(manager.openAICompatibleKeyStorageError)
        XCTAssertEqual(
            keychain.storedValue(for: "settings.openAICompatible.apiKey.v1"),
            "synthetic-current-key"
        )
        XCTAssertEqual(isolatedDefaults.string(forKey: "openAICompatibleAPIKey"), "synthetic-stale-legacy-key")

        // An unrelated settings save must not delete the key just because the field is
        // empty — the field is empty only because the read failed.
        manager.openAICompatibleContextSize = 16384
        manager.saveSettings()
        XCTAssertEqual(
            keychain.storedValue(for: "settings.openAICompatible.apiKey.v1"),
            "synthetic-current-key"
        )

        // Entering a key replaces the unreadable item and clears the warning.
        keychain.retrieveError = nil
        manager.openAICompatibleAPIKey = "synthetic-replacement-key"
        manager.saveSettings()
        XCTAssertNil(manager.openAICompatibleKeyStorageError)
        XCTAssertEqual(
            keychain.storedValue(for: "settings.openAICompatible.apiKey.v1"),
            "synthetic-replacement-key"
        )
        XCTAssertNil(isolatedDefaults.string(forKey: "openAICompatibleAPIKey"))
    }

    func testResetRemovesAnUnreadableAPIKey() {
        let name = "SettingsManagerTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: name) else {
            XCTFail("Unable to create an isolated UserDefaults suite")
            return
        }
        addTeardownBlock { isolatedDefaults.removePersistentDomain(forName: name) }
        isolatedDefaults.set("synthetic-stale-legacy-key", forKey: "openAICompatibleAPIKey")

        let keychain = InMemoryKeychain()
        try? keychain.store(string: "synthetic-current-key", for: "settings.openAICompatible.apiKey.v1")
        keychain.retrieveError = KeychainError.retrieveFailed(errSecIO)

        let manager = SettingsManager(userDefaults: isolatedDefaults, keychain: keychain)
        XCTAssertNotNil(manager.openAICompatibleKeyStorageError)

        // An explicit reset is a deliberate request to remove the key, so it must go
        // through even though the stored item could not be read. Otherwise the key
        // reappears the next time a read succeeds.
        manager.resetServerSettings()

        XCTAssertNil(keychain.storedValue(for: "settings.openAICompatible.apiKey.v1"))
        XCTAssertNil(isolatedDefaults.string(forKey: "openAICompatibleAPIKey"))
        XCTAssertNil(manager.openAICompatibleKeyStorageError)
        XCTAssertTrue(manager.openAICompatibleAPIKey.isEmpty)
    }

    func testUnreadableAPIKeyIsRetriedRatherThanLatchedForTheSession() {
        // The item is stored WhenUnlockedThisDeviceOnly, so a launch while the device is
        // locked fails the read. Latching that would leave the key unusable until the
        // process restarts, with every request going out unauthenticated.
        let name = "SettingsManagerTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: name) else {
            XCTFail("Unable to create an isolated UserDefaults suite")
            return
        }
        addTeardownBlock { isolatedDefaults.removePersistentDomain(forName: name) }

        let keychain = InMemoryKeychain()
        try? keychain.store(string: "synthetic-current-key", for: "settings.openAICompatible.apiKey.v1")
        keychain.retrieveError = KeychainError.retrieveFailed(errSecInteractionNotAllowed)

        let manager = SettingsManager(userDefaults: isolatedDefaults, keychain: keychain)
        XCTAssertTrue(manager.openAICompatibleAPIKey.isEmpty)
        XCTAssertNotNil(manager.openAICompatibleKeyStorageError)

        // While still locked, the retry reports failure and changes nothing.
        XCTAssertFalse(manager.reloadAPIKeyIfUnreadable())
        XCTAssertTrue(manager.openAICompatibleAPIKey.isEmpty)

        // Once the device unlocks, the key becomes available without a relaunch.
        keychain.retrieveError = nil
        XCTAssertTrue(manager.reloadAPIKeyIfUnreadable())
        XCTAssertEqual(manager.openAICompatibleAPIKey, "synthetic-current-key")
        XCTAssertNil(manager.openAICompatibleKeyStorageError)
    }

    func testRetryDoesNotOverwriteAKeyTheUserTypedWhileStorageWasUnreadable() {
        let name = "SettingsManagerTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: name) else {
            XCTFail("Unable to create an isolated UserDefaults suite")
            return
        }
        addTeardownBlock { isolatedDefaults.removePersistentDomain(forName: name) }

        let keychain = InMemoryKeychain()
        try? keychain.store(string: "synthetic-old-key", for: "settings.openAICompatible.apiKey.v1")
        keychain.retrieveError = KeychainError.retrieveFailed(errSecInteractionNotAllowed)

        let manager = SettingsManager(userDefaults: isolatedDefaults, keychain: keychain)
        manager.openAICompatibleAPIKey = "synthetic-user-entered-key"

        keychain.retrieveError = nil
        XCTAssertTrue(manager.reloadAPIKeyIfUnreadable())
        XCTAssertEqual(manager.openAICompatibleAPIKey, "synthetic-user-entered-key")
    }

    func testKeychainStoreUpdatesInPlaceWithoutDeletingFirst() throws {
        // The write must not be delete-then-add: an add that failed after the delete
        // succeeded would destroy the previous value. Repeated writes should therefore
        // update one item rather than recreate it.
        let keychain = Keychain()
        let account = "SettingsManagerTests.rotation.\(UUID().uuidString)"
        addTeardownBlock { try? keychain.delete(for: account) }

        try keychain.store(string: "synthetic-first-value", for: account)
        XCTAssertEqual(try keychain.retrieveString(for: account), "synthetic-first-value")

        try keychain.store(string: "synthetic-second-value", for: account)
        XCTAssertEqual(try keychain.retrieveString(for: account), "synthetic-second-value")

        try keychain.delete(for: account)
        XCTAssertNil(try keychain.retrieveString(for: account))

        // Deleting an item that is not there is not an error.
        XCTAssertNoThrow(try keychain.delete(for: account))
    }

    func testFailedKeychainDeletionIsNotReportedAsACleanedKey() {
        let name = "SettingsManagerTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: name) else {
            XCTFail("Unable to create an isolated UserDefaults suite")
            return
        }
        addTeardownBlock { isolatedDefaults.removePersistentDomain(forName: name) }
        isolatedDefaults.set("synthetic-legacy-api-key", forKey: "openAICompatibleAPIKey")

        let keychain = InMemoryKeychain()
        let manager = SettingsManager(userDefaults: isolatedDefaults, keychain: keychain)
        XCTAssertNil(manager.openAICompatibleKeyStorageError)

        keychain.deleteError = KeychainError.deleteFailed(errSecIO)
        manager.openAICompatibleAPIKey = ""
        manager.saveSettings()

        // The secure copy survived, so the key must not be presented as cleared and the
        // legacy copy must not be dropped on the strength of a failed deletion.
        XCTAssertNotNil(manager.openAICompatibleKeyStorageError)
        XCTAssertEqual(
            try? keychain.retrieveString(for: "settings.openAICompatible.apiKey.v1"),
            "synthetic-legacy-api-key"
        )

        // Once deletion succeeds, both copies go and the error clears.
        keychain.deleteError = nil
        manager.saveSettings()
        XCTAssertNil(manager.openAICompatibleKeyStorageError)
        XCTAssertNil(try? keychain.retrieveString(for: "settings.openAICompatible.apiKey.v1"))
        XCTAssertNil(isolatedDefaults.string(forKey: "openAICompatibleAPIKey"))
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
