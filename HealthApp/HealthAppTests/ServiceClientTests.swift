import XCTest
import Security
@testable import HealthApp

@MainActor
final class ServiceClientTests: XCTestCase {

    private func makeUserDefaults() -> (UserDefaults, String) {
        let suiteName = "AWSCredentialsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        return (defaults, suiteName)
    }

    private func makeCredentials(sessionToken: String? = nil) -> AWSCredentials {
        AWSCredentials(
            accessKeyId: "synthetic-access-key",
            secretAccessKey: "synthetic-secret-key",
            sessionToken: sessionToken,
            region: "us-east-1"
        )
    }

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

    func testAWSCredentialsSaveAndLoadThroughInjectedStorage() {
        let storage = MockAWSCredentialsStorage()
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        let credentials = makeCredentials()

        if case .failure(let error) = manager.updateCredentials(credentials) {
            XCTFail("Unexpected credential storage error: \(error.localizedDescription)")
        }
        XCTAssertEqual(storage.storedCredentials, credentials)
        XCTAssertEqual(manager.credentials, credentials)
        XCTAssertNil(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey))
    }

    func testAWSCredentialsMigrateLegacyUserDefaultsAndRemoveAfterVerification() throws {
        let storage = MockAWSCredentialsStorage()
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyCredentials = makeCredentials(sessionToken: "synthetic-session-token")
        defaults.set(try JSONEncoder().encode(legacyCredentials), forKey: AWSCredentialsManager.legacyCredentialsKey)

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)

        XCTAssertEqual(manager.credentials, legacyCredentials)
        XCTAssertEqual(storage.storedCredentials, legacyCredentials)
        XCTAssertNil(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey))
        XCTAssertNil(manager.lastError)
    }

    func testAWSCredentialsFailedSavePreservesLegacyValue() throws {
        let storage = MockAWSCredentialsStorage()
        storage.saveError = .keychainError(errSecIO)
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyData = try JSONEncoder().encode(makeCredentials())
        defaults.set(legacyData, forKey: AWSCredentialsManager.legacyCredentialsKey)

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)

        XCTAssertEqual(manager.lastError, .keychainError(errSecIO))
        XCTAssertEqual(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey), legacyData)
    }

    func testAWSCredentialsFailedVerificationPreservesLegacyValue() throws {
        let storage = MockAWSCredentialsStorage()
        storage.readBackCredentials = AWSCredentials(
            accessKeyId: "different-access-key",
            secretAccessKey: "different-secret-key",
            region: "us-east-1"
        )
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyData = try JSONEncoder().encode(makeCredentials())
        defaults.set(legacyData, forKey: AWSCredentialsManager.legacyCredentialsKey)

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)

        XCTAssertEqual(manager.lastError, .verificationFailed)
        XCTAssertEqual(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey), legacyData)
    }

    func testAWSCredentialsRemoveMatchingLegacyValueAfterKeychainRecovery() throws {
        let credentials = makeCredentials(sessionToken: "synthetic-session-token")
        let storage = MockAWSCredentialsStorage()
        storage.storedCredentials = credentials
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONEncoder().encode(credentials),
            forKey: AWSCredentialsManager.legacyCredentialsKey
        )

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)

        XCTAssertEqual(manager.credentials, credentials)
        XCTAssertNil(manager.lastError)
        XCTAssertNil(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey))
    }

    func testAWSCredentialsPreserveAndReportConflictingLegacyValue() throws {
        let keychainCredentials = makeCredentials()
        let conflictingLegacyCredentials = AWSCredentials(
            accessKeyId: "different-synthetic-access-key",
            secretAccessKey: "different-synthetic-secret-key",
            region: "us-west-2"
        )
        let legacyData = try JSONEncoder().encode(conflictingLegacyCredentials)
        let storage = MockAWSCredentialsStorage()
        storage.storedCredentials = keychainCredentials
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(legacyData, forKey: AWSCredentialsManager.legacyCredentialsKey)

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)

        XCTAssertEqual(manager.credentials, keychainCredentials)
        XCTAssertEqual(manager.lastError, .legacyCredentialConflict)
        XCTAssertEqual(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey), legacyData)
    }

    func testLegacyConflictIsOnlyResolvedByAnExplicitChoice() throws {
        // Two different credential sets exist and only the user knows which is wanted,
        // so nothing short of a deliberate action may discard either one.
        let keychainCredentials = makeCredentials()
        let conflicting = AWSCredentials(
            accessKeyId: "different-synthetic-access-key",
            secretAccessKey: "different-synthetic-secret-key",
            region: "us-west-2"
        )
        let legacyData = try JSONEncoder().encode(conflicting)
        let storage = MockAWSCredentialsStorage()
        storage.storedCredentials = keychainCredentials
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(legacyData, forKey: AWSCredentialsManager.legacyCredentialsKey)

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertEqual(manager.lastError, .legacyCredentialConflict)

        // Staging (an unfinished edit) must not resolve it.
        manager.stageCredentials(keychainCredentials)
        XCTAssertEqual(manager.lastError, .legacyCredentialConflict)
        XCTAssertEqual(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey), legacyData)

        // The explicit choice does.
        if case .failure(let error) = manager.resolveLegacyConflictKeepingCurrent() {
            XCTFail("Resolving the conflict should succeed: \(error.localizedDescription)")
        }
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(manager.credentials, keychainCredentials)
        XCTAssertNil(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey))
    }

    func testFailedSaveCanBeRetriedWithUnchangedCredentials() {
        // updateCredentials assigns before it persists, so after a failure the edited
        // pair equals the in-memory one. Without an unsaved marker the screen, which has
        // no separate save button, could never retry a transient Keychain failure.
        let storage = MockAWSCredentialsStorage()
        storage.saveError = .keychainError(errSecIO)
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertFalse(manager.hasUnsavedChanges)

        let credentials = makeCredentials()
        guard case .failure = manager.updateCredentials(credentials) else {
            XCTFail("Expected the save to fail")
            return
        }
        XCTAssertTrue(manager.hasUnsavedChanges)
        XCTAssertEqual(manager.credentials, credentials)
        XCTAssertNil(storage.storedCredentials)

        // The same pair, retried once storage recovers, now persists.
        storage.saveError = nil
        if case .failure(let error) = manager.updateCredentials(credentials) {
            XCTFail("Retry should succeed: \(error.localizedDescription)")
        }
        XCTAssertFalse(manager.hasUnsavedChanges)
        XCTAssertEqual(storage.storedCredentials, credentials)
    }

    func testResolvingConflictIsANoOpWhenNoConflictExists() {
        let storage = MockAWSCredentialsStorage()
        storage.storedCredentials = makeCredentials()
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertNil(manager.lastError)

        if case .failure = manager.resolveLegacyConflictKeepingCurrent() {
            XCTFail("Resolving without a conflict should be a no-op")
        }
        XCTAssertNil(manager.lastError)
    }

    func testResavingUnchangedCredentialsResolvesALegacyConflict() throws {
        // The conflict warning tells the user to re-enter and save. The form is
        // prefilled from the Keychain, so that save carries unchanged values and must
        // still clear the plaintext copy and the warning.
        let keychainCredentials = makeCredentials()
        let conflicting = AWSCredentials(
            accessKeyId: "different-synthetic-access-key",
            secretAccessKey: "different-synthetic-secret-key",
            region: "us-west-2"
        )
        let storage = MockAWSCredentialsStorage()
        storage.storedCredentials = keychainCredentials
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(conflicting), forKey: AWSCredentialsManager.legacyCredentialsKey)

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertEqual(manager.lastError, .legacyCredentialConflict)

        if case .failure(let error) = manager.updateCredentials(manager.credentials) {
            XCTFail("Re-saving the loaded credentials should succeed: \(error.localizedDescription)")
        }

        XCTAssertNil(manager.lastError)
        XCTAssertNil(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey))
    }

    func testAWSCredentialsDeletionRemovesKeychainAndLegacyCopies() throws {
        let storage = MockAWSCredentialsStorage()
        storage.storedCredentials = makeCredentials()
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(makeCredentials()), forKey: AWSCredentialsManager.legacyCredentialsKey)

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        if case .failure(let error) = manager.deleteCredentials() {
            XCTFail("Unexpected credential deletion error: \(error.localizedDescription)")
        }

        XCTAssertNil(storage.storedCredentials)
        XCTAssertNil(defaults.data(forKey: AWSCredentialsManager.legacyCredentialsKey))
        XCTAssertEqual(manager.credentials, .default)
    }

    func testAWSCredentialsReportStoredMaterialForClearDetection() throws {
        let storage = MockAWSCredentialsStorage()
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let empty = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertFalse(empty.hasStoredCredentials)

        storage.storedCredentials = makeCredentials()
        let populated = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertTrue(populated.hasStoredCredentials)

        // A legacy plaintext copy alone still counts as material to remove.
        let legacyOnlyStorage = MockAWSCredentialsStorage()
        let (legacyDefaults, legacySuite) = makeUserDefaults()
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        legacyDefaults.set(
            try JSONEncoder().encode(makeCredentials()),
            forKey: AWSCredentialsManager.legacyCredentialsKey
        )
        let migrated = AWSCredentialsManager(storage: legacyOnlyStorage, userDefaults: legacyDefaults)
        XCTAssertTrue(migrated.hasStoredCredentials)
    }

    func testMalformedKeychainCredentialsCanStillBeCleared() {
        // A Keychain item that fails to decode leaves the in-memory value at .default.
        // Inferring "nothing stored" from that would make the material impossible to
        // remove through the settings screen, which only deletes when something is held.
        let storage = MockAWSCredentialsStorage()
        storage.loadError = .invalidData
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertEqual(manager.credentials, .default)
        XCTAssertTrue(manager.hasStoredCredentials, "Unreadable material still needs removing")

        storage.storedCredentials = makeCredentials()
        if case .failure(let error) = manager.deleteCredentials() {
            XCTFail("Deleting unreadable credentials should succeed: \(error.localizedDescription)")
        }
        XCTAssertNil(storage.storedCredentials)
        XCTAssertFalse(manager.hasStoredCredentials)
    }

    func testUnreadableCredentialsAreRetriedRatherThanLatched() {
        let storage = MockAWSCredentialsStorage()
        storage.loadError = .keychainError(errSecInteractionNotAllowed)
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        XCTAssertEqual(manager.credentials, .default)
        XCTAssertFalse(manager.reloadIfUnreadable())

        // Once the Keychain becomes available the credentials load without a relaunch.
        let credentials = makeCredentials()
        storage.loadError = nil
        storage.storedCredentials = credentials
        XCTAssertTrue(manager.reloadIfUnreadable())
        XCTAssertEqual(manager.credentials, credentials)
        XCTAssertNil(manager.lastError)
    }

    func testStagingCredentialsDoesNotRemoveTheStoredPair() {
        // Staging is for an unfinished edit; only an explicit delete may remove material.
        let storage = MockAWSCredentialsStorage()
        storage.storedCredentials = makeCredentials()
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)
        manager.stageCredentials(AWSCredentials(
            accessKeyId: "",
            secretAccessKey: "synthetic-secret-key",
            region: "us-east-1"
        ))

        XCTAssertNotNil(storage.storedCredentials)
        XCTAssertTrue(manager.hasStoredCredentials)
    }

    func testAWSCredentialsValidationRejectsEmptyAndPartialValues() {
        let empty = AWSCredentials(accessKeyId: "", secretAccessKey: "synthetic-secret-key", region: "us-east-1")
        let partial = AWSCredentials(accessKeyId: "synthetic-access-key", secretAccessKey: "", region: "us-east-1")

        XCTAssertFalse(empty.isValid)
        XCTAssertFalse(partial.isValid)

        let storage = MockAWSCredentialsStorage()
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = AWSCredentialsManager(storage: storage, userDefaults: defaults)

        guard case .failure(.validationFailed(["Secret key is required"])) = manager.updateCredentials(partial) else {
            XCTFail("Expected partial credentials to fail validation")
            return
        }
        XCTAssertNil(storage.storedCredentials)
    }

    func testBedrockUsesOptionalSessionTokenWithoutWritingAWSEnvironmentVariables() async throws {
        let credentials = makeCredentials(sessionToken: "synthetic-session-token")
        let bedrockConfig = AWSBedrockConfig(
            region: credentials.region,
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken,
            model: .claudeSonnet45,
            temperature: 0.1,
            maxTokens: 50,
            timeout: 30
        )
        let environmentKeys = [
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_SESSION_TOKEN",
            "AWS_DEFAULT_REGION"
        ]
        let environmentBefore = environmentKeys.map { ProcessInfo.processInfo.environment[$0] }

        let clientConfig = try await BedrockClient.makeClientConfig(for: bedrockConfig)
        let identity = try await clientConfig.awsCredentialIdentityResolver.getIdentity(identityProperties: nil)

        XCTAssertEqual(identity.accessKey, credentials.accessKeyId)
        XCTAssertEqual(identity.secret, credentials.secretAccessKey)
        XCTAssertEqual(identity.sessionToken, credentials.sessionToken)
        XCTAssertEqual(environmentKeys.map { ProcessInfo.processInfo.environment[$0] }, environmentBefore)
    }

    func testBedrockConfigurationRequiresExplicitCredentials() {
        let config = AWSBedrockConfig(
            region: "us-east-1",
            accessKeyId: "",
            secretAccessKey: "",
            sessionToken: nil,
            model: .claudeSonnet45,
            temperature: 0.1,
            maxTokens: 50,
            timeout: 30
        )

        XCTAssertFalse(config.isValid)
    }

    func testOpenAICompatibleFailureOmitsRawResponseBodyFromLocalizedDescription() {
        let rawResponseBody = #"{"error":{"message":"patient: Synthetic Patient, authorization: Bearer synthetic-api-key"}}"#
        guard let response = syntheticHTTPResponse(
            statusCode: 502,
            headers: ["x-request-id": "synthetic-request-id-123"]
        ) else {
            XCTFail("Unable to create synthetic HTTP response")
            return
        }

        let error = OpenAICompatibleError.requestFailed(response: response)
        let description = error.localizedDescription

        XCTAssertFalse(description.contains(rawResponseBody))
        XCTAssertFalse(description.contains("Synthetic Patient"))
        XCTAssertFalse(description.contains("synthetic-api-key"))
        XCTAssertTrue(description.contains("HTTP 502"))
        XCTAssertTrue(description.contains("OpenAI-compatible"))
        XCTAssertTrue(description.contains("synthetic-request-id-123"))
    }

    func testOpenAICompatibleFailureRemovesAuthorizationValues() {
        let error = OpenAICompatibleError.requestFailed(
            401,
            "authorization: Bearer synthetic-api-key"
        )
        let description = error.localizedDescription

        XCTAssertTrue(description.contains("HTTP 401"))
        XCTAssertFalse(description.contains("synthetic-api-key"))
        XCTAssertFalse(description.contains("Bearer synthetic-api-key"))
    }

    func testOpenAICompatibleProviderMessagesAreStrictlyBounded() {
        let largeProviderMessage = String(repeating: "synthetic-provider-error ", count: 1_000)
        let error = OpenAICompatibleError.requestFailed(503, largeProviderMessage)

        XCTAssertLessThanOrEqual(error.localizedDescription.count, 512)
    }

    func testOpenAICompatibleMalformedResponseIsSafe() {
        let malformedBody = "not-json patient: Synthetic Patient authorization: Bearer synthetic-api-key"
        let error = OpenAICompatibleError.invalidResponse

        XCTAssertEqual(error.localizedDescription, "Invalid response from server")
        XCTAssertFalse(error.localizedDescription.contains(malformedBody))
        XCTAssertFalse(error.localizedDescription.contains("Synthetic Patient"))
        XCTAssertFalse(error.localizedDescription.contains("synthetic-api-key"))
    }

    func testAppLogRedactsSyntheticProviderContentFromPersistedAndExportedLogs() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLogTests-\(UUID().uuidString)", isDirectory: true)
        let logger = AppLog(
            logDirectory: rootURL.appendingPathComponent("Logs", isDirectory: true),
            errorBufferURL: rootURL.appendingPathComponent("error-buffer.log"),
            metricKitDiagnosticsURL: rootURL.appendingPathComponent("metric-kit.log")
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let syntheticProviderContent = "Provider response: patient: Synthetic Patient, date of birth: 2000-01-01, authorization: Bearer synthetic-api-key"
        logger.error(syntheticProviderContent, category: .ai)

        let retainedContent = [
            logger.getCurrentLogContent(),
            logger.getCombinedLogFileContent(),
            logger.getErrorBufferContent()
        ].compactMap { $0 }.joined(separator: "\n")

        XCTAssertFalse(retainedContent.contains("Synthetic Patient"))
        XCTAssertFalse(retainedContent.contains("2000-01-01"))
        XCTAssertFalse(retainedContent.contains("synthetic-api-key"))
        XCTAssertTrue(retainedContent.contains("[REDACTED"))
    }

    func testAppLogDoesNotPersistArbitraryProviderErrorDescriptions() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLogErrorTests-\(UUID().uuidString)", isDirectory: true)
        let logger = AppLog(
            logDirectory: rootURL.appendingPathComponent("Logs", isDirectory: true),
            errorBufferURL: rootURL.appendingPathComponent("error-buffer.log"),
            metricKitDiagnosticsURL: rootURL.appendingPathComponent("metric-kit.log")
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let syntheticProviderContent = "patient: Synthetic Patient, authorization: Bearer synthetic-api-key"
        let error = NSError(
            domain: "SyntheticProvider",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: syntheticProviderContent]
        )
        logger.error("Synthetic connection failure", error: error, category: .ai)

        let retainedContent = [
            logger.getCurrentLogContent(),
            logger.getCombinedLogFileContent(),
            logger.getErrorBufferContent()
        ].compactMap { $0 }.joined(separator: "\n")

        XCTAssertFalse(retainedContent.contains("Synthetic Patient"))
        XCTAssertFalse(retainedContent.contains("synthetic-api-key"))
        XCTAssertTrue(retainedContent.contains("Underlying error type"))
    }

    func testAppLogPrunesExpiredErrorAndMetricKitEntriesOnInitialization() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLogRetentionTests-\(UUID().uuidString)", isDirectory: true)
        let logsURL = rootURL.appendingPathComponent("Logs", isDirectory: true)
        let errorBufferURL = rootURL.appendingPathComponent("error-buffer.log")
        let metricKitURL = rootURL.appendingPathComponent("metric-kit.log")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let formatter = ISO8601DateFormatter()
        let oldTimestamp = formatter.string(from: Date(timeIntervalSinceNow: -(31 * 24 * 60 * 60)))
        let recentTimestamp = formatter.string(from: Date(timeIntervalSinceNow: -(24 * 60 * 60)))
        let oldError = "[\(oldTimestamp)] [ERROR] [General] expired-error"
        let recentError = "[\(recentTimestamp)] [ERROR] [General] recent-error"
        try "\(oldError)\n\(recentError)\n".write(to: errorBufferURL, atomically: true, encoding: .utf8)

        let oldMetric = "\n--- MetricKit Diagnostic \(oldTimestamp) ---\nexpired-metric\n"
        let recentMetric = "\n--- MetricKit Diagnostic \(recentTimestamp) ---\nrecent-metric\n"
        try "\(oldMetric)\(recentMetric)".write(to: metricKitURL, atomically: true, encoding: .utf8)

        let logger = AppLog(
            logDirectory: logsURL,
            errorBufferURL: errorBufferURL,
            metricKitDiagnosticsURL: metricKitURL
        )

        let retainedErrors = logger.getErrorBufferContent() ?? ""
        XCTAssertFalse(retainedErrors.contains("expired-error"))
        XCTAssertTrue(retainedErrors.contains("recent-error"))

        let retainedMetrics = logger.getMetricKitDiagnosticsContent() ?? ""
        XCTAssertFalse(retainedMetrics.contains("expired-metric"))
        XCTAssertTrue(retainedMetrics.contains("recent-metric"))
    }

    func testAppLogPrunesExpiredFileLogsOnInitialization() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLogFileRetentionTests-\(UUID().uuidString)", isDirectory: true)
        let logsURL = rootURL.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let expiredLogURL = logsURL.appendingPathComponent("app-expired.log")
        try "expired-file-log\n".write(to: expiredLogURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -(8 * 24 * 60 * 60))],
            ofItemAtPath: expiredLogURL.path
        )

        _ = AppLog(
            logDirectory: logsURL,
            errorBufferURL: rootURL.appendingPathComponent("error-buffer.log"),
            metricKitDiagnosticsURL: rootURL.appendingPathComponent("metric-kit.log")
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredLogURL.path))
    }

    func testProviderRequestIdentifierIsWithheldFromDurableLogs() {
        // A request ID is untrusted response data: a character allowlist cannot show it
        // is free of PHI, so it may inform the user but must not be persisted.
        guard let response = syntheticHTTPResponse(
            statusCode: 502,
            headers: ["x-request-id": "JaneDoe-MRN123"]
        ) else {
            XCTFail("Unable to create synthetic HTTP response")
            return
        }

        let error = OpenAICompatibleError.requestFailed(response: response)

        XCTAssertTrue(error.localizedDescription.contains("JaneDoe-MRN123"))
        XCTAssertFalse(error.loggableDescription.contains("JaneDoe-MRN123"))
        XCTAssertTrue(error.loggableDescription.contains("HTTP 502"))
        XCTAssertEqual(AppLog.sanitizedErrorDescription(error), error.loggableDescription)
    }

    func testProviderRequestIdentifierNeverReachesPersistedLogs() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLogRequestIDTests-\(UUID().uuidString)", isDirectory: true)
        let logger = AppLog(
            logDirectory: rootURL.appendingPathComponent("Logs", isDirectory: true),
            errorBufferURL: rootURL.appendingPathComponent("error-buffer.log"),
            metricKitDiagnosticsURL: rootURL.appendingPathComponent("metric-kit.log")
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        guard let response = syntheticHTTPResponse(
            statusCode: 500,
            headers: ["x-request-id": "JaneDoe-MRN123"]
        ) else {
            XCTFail("Unable to create synthetic HTTP response")
            return
        }
        logger.error(
            "OpenAI-compatible chat request failed",
            error: OpenAICompatibleError.requestFailed(response: response),
            category: .ai
        )

        let retainedContent = [
            logger.getCurrentLogContent(),
            logger.getCombinedLogFileContent(),
            logger.getErrorBufferContent()
        ].compactMap { $0 }.joined(separator: "\n")

        XCTAssertFalse(retainedContent.contains("JaneDoe-MRN123"))
        XCTAssertTrue(retainedContent.contains("HTTP 500"))
    }

    func testProviderURLDiagnosticsKeepOnlyTheEndpointIdentity() {
        // A configured base URL can carry a proxy token or PHI in its path, and these
        // strings are written to log files where the generic redactor cannot scrub an
        // arbitrary path.
        let cases: [(String, String)] = [
            ("https://host.example.test/patient/MRN123/v1/chat/completions", "https://host.example.test"),
            ("https://host.example.test:8443/proxy/secret-token/v1", "https://host.example.test:8443"),
            ("http://192.168.1.10:11434/v1/models", "http://192.168.1.10:11434"),
            ("https://user:pass@host.example.test/v1?key=synthetic", "https://host.example.test"),
            ("http://[fd00::1]:8000/v1/chat", "http://[fd00::1]:8000")
        ]

        for (raw, expected) in cases {
            guard let url = URL(string: raw) else {
                XCTFail("Unable to build \(raw)")
                continue
            }
            let described = OpenAICompatibleClient.safeURLDescription(url)
            XCTAssertEqual(described, expected)
            XCTAssertFalse(described.contains("MRN123"))
            XCTAssertFalse(described.contains("secret-token"))
            XCTAssertFalse(described.contains("pass"))
            XCTAssertFalse(described.contains("synthetic"))
        }
    }

    func testRedactionCoversJSONQuotedProviderValues() {
        // Regression: the closing delimiter in this rule was written as the literal
        // two-character sequence `"'` instead of a character class, so quoted JSON
        // values — the exact shape a provider error body takes — were never redacted.
        let cases = [
            #"{"message": "patient John Doe, glucose 92"}"#,
            #"{"error": "upstream said: Synthetic Patient"}"#,
            "{'detail': 'Synthetic Patient record'}",
            #"response: "raw provider body with Synthetic Patient""#
        ]

        for rawText in cases {
            let redacted = AppLog.redactForSupport(rawText)
            XCTAssertTrue(redacted.contains("[REDACTED]"), "Not redacted: \(rawText)")
            XCTAssertFalse(redacted.contains("Synthetic Patient"), "Leaked name: \(redacted)")
            XCTAssertFalse(redacted.contains("John Doe"), "Leaked name: \(redacted)")
        }
    }

    func testRedactionLeavesUnquotedTextWithMatchedDelimitersIntact() {
        // The rule only applies to a quoted value, and the closing quote must match
        // the opening one, so an unterminated value cannot swallow the rest of a line.
        let redacted = AppLog.redactForSupport(#"status: ok, message: "first", tail: keep-me"#)

        XCTAssertTrue(redacted.contains("keep-me"))
    }

    private func syntheticHTTPResponse(statusCode: Int, headers: [String: String] = [:]) -> HTTPURLResponse? {
        guard let url = URL(string: "https://provider.example.test/v1/models") else {
            return nil
        }
        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )
    }
}

private final class MockAWSCredentialsStorage: AWSCredentialsStorage {
    var storedCredentials: AWSCredentials?
    var readBackCredentials: AWSCredentials?
    var saveError: AWSCredentialsError?
    var deleteError: AWSCredentialsError?
    var loadError: AWSCredentialsError?

    func loadCredentials() throws -> AWSCredentials? {
        if let loadError { throw loadError }
        if storedCredentials != nil, let readBackCredentials {
            return readBackCredentials
        }
        return storedCredentials
    }

    func saveCredentials(_ credentials: AWSCredentials) throws {
        if let saveError {
            throw saveError
        }
        storedCredentials = credentials
    }

    func deleteCredentials() throws {
        if let deleteError {
            throw deleteError
        }
        storedCredentials = nil
    }
}
