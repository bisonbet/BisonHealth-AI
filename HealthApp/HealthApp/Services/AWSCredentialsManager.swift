//
//  AWSCredentialsManager.swift
//  HealthApp
//
//  Unified AWS credentials management for all AWS services in health app
//

import Foundation

// MARK: - Shared AWS Configuration

struct AWSCredentials: Equatable, Codable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let region: String

    init(
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        region: String
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.region = region
    }

    var isValid: Bool {
        AWSCredentialsHelper.validateCredentials(self).isValid
    }

    static let `default` = AWSCredentials(
        accessKeyId: "",
        secretAccessKey: "",
        sessionToken: nil,
        region: "us-east-1"
    )
}

// MARK: - AWS Credentials Manager

final class AWSCredentialsManager: ObservableObject {
    static let legacyCredentialsKey = "AWSCredentials"

    @Published var credentials: AWSCredentials
    @Published private(set) var lastError: AWSCredentialsError?

    private let storage: any AWSCredentialsStorage
    private let userDefaults: UserDefaults

    init(
        storage: any AWSCredentialsStorage = AWSCredentialsHelper(),
        userDefaults: UserDefaults = .standard
    ) {
        self.storage = storage
        self.userDefaults = userDefaults

        do {
            let result = try Self.loadStoredCredentials(storage: storage, userDefaults: userDefaults)
            self.credentials = result.credentials ?? .default
            self.lastError = result.warning
        } catch let error as AWSCredentialsError {
            self.credentials = .default
            self.lastError = error
        } catch {
            self.credentials = .default
            self.lastError = .storageUnavailable
        }
    }

    // MARK: - Credential Updates

    @discardableResult
    func updateCredentials(_ newCredentials: AWSCredentials) -> Result<Void, AWSCredentialsError> {
        // Keep field-by-field editing responsive, but never persist an incomplete value.
        credentials = newCredentials

        let validation = AWSCredentialsHelper.validateCredentials(newCredentials)
        guard validation.isValid else {
            let error = AWSCredentialsError.validationFailed(validation.issues)
            lastError = error
            return .failure(error)
        }

        do {
            try persistAndVerify(newCredentials)
            lastError = nil
            return .success(())
        } catch let error as AWSCredentialsError {
            lastError = error
            return .failure(error)
        } catch {
            lastError = .storageUnavailable
            return .failure(.storageUnavailable)
        }
    }

    @discardableResult
    func updateAccessKey(_ accessKey: String) -> Result<Void, AWSCredentialsError> {
        updateCredentials(AWSCredentials(
            accessKeyId: accessKey,
            secretAccessKey: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken,
            region: credentials.region
        ))
    }

    @discardableResult
    func updateSecretKey(_ secretKey: String) -> Result<Void, AWSCredentialsError> {
        updateCredentials(AWSCredentials(
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: secretKey,
            sessionToken: credentials.sessionToken,
            region: credentials.region
        ))
    }

    @discardableResult
    func updateRegion(_ region: String) -> Result<Void, AWSCredentialsError> {
        updateCredentials(AWSCredentials(
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken,
            region: region
        ))
    }

    @discardableResult
    func deleteCredentials() -> Result<Void, AWSCredentialsError> {
        do {
            // Preserve the legacy value if current Keychain deletion fails.
            try storage.deleteCredentials()
            userDefaults.removeObject(forKey: Self.legacyCredentialsKey)
            credentials = .default
            lastError = nil
            return .success(())
        } catch let error as AWSCredentialsError {
            lastError = error
            return .failure(error)
        } catch {
            lastError = .storageUnavailable
            return .failure(.storageUnavailable)
        }
    }

    // MARK: - Migration

    private struct StoredCredentialsResult {
        let credentials: AWSCredentials?
        let warning: AWSCredentialsError?
    }

    private static func loadStoredCredentials(
        storage: any AWSCredentialsStorage,
        userDefaults: UserDefaults
    ) throws -> StoredCredentialsResult {
        // 1. Keychain is authoritative.
        if let keychainCredentials = try storage.loadCredentials() {
            let validation = AWSCredentialsHelper.validateCredentials(keychainCredentials)
            guard validation.isValid else {
                throw AWSCredentialsError.validationFailed(validation.issues)
            }

            guard let legacyData = userDefaults.data(forKey: legacyCredentialsKey) else {
                return StoredCredentialsResult(credentials: keychainCredentials, warning: nil)
            }

            guard let legacyCredentials = try? JSONDecoder().decode(AWSCredentials.self, from: legacyData),
                  AWSCredentialsHelper.validateCredentials(legacyCredentials).isValid,
                  legacyCredentials == keychainCredentials else {
                // Keep a conflicting legacy value for explicit user recovery instead of
                // silently deleting credential material that could still be needed.
                return StoredCredentialsResult(
                    credentials: keychainCredentials,
                    warning: .legacyCredentialConflict
                )
            }

            // A previous migration may have succeeded even if its immediate read-back
            // verification failed. Remove the matching plaintext copy on recovery.
            userDefaults.removeObject(forKey: legacyCredentialsKey)
            return StoredCredentialsResult(credentials: keychainCredentials, warning: nil)
        }

        // 2. Only when Keychain is absent, inspect the legacy UserDefaults value.
        guard let legacyData = userDefaults.data(forKey: legacyCredentialsKey) else {
            return StoredCredentialsResult(credentials: nil, warning: nil)
        }

        // 3. Decode and validate before attempting migration.
        let legacyCredentials: AWSCredentials
        do {
            legacyCredentials = try JSONDecoder().decode(AWSCredentials.self, from: legacyData)
        } catch {
            throw AWSCredentialsError.invalidData
        }

        let validation = AWSCredentialsHelper.validateCredentials(legacyCredentials)
        guard validation.isValid else {
            throw AWSCredentialsError.validationFailed(validation.issues)
        }

        // 4. Save to Keychain.
        try storage.saveCredentials(legacyCredentials)

        // 5. Read back and verify the exact saved value.
        guard let verifiedCredentials = try storage.loadCredentials(),
              verifiedCredentials == legacyCredentials else {
            // 6. Do not remove the legacy value if verification failed.
            throw AWSCredentialsError.verificationFailed
        }

        // 6. Remove the legacy value only after successful verification.
        userDefaults.removeObject(forKey: legacyCredentialsKey)
        return StoredCredentialsResult(credentials: verifiedCredentials, warning: nil)
    }

    private func persistAndVerify(_ newCredentials: AWSCredentials) throws {
        // A save or read-back failure leaves any legacy value untouched.
        try storage.saveCredentials(newCredentials)
        guard let verifiedCredentials = try storage.loadCredentials(),
              verifiedCredentials == newCredentials else {
            throw AWSCredentialsError.verificationFailed
        }
        userDefaults.removeObject(forKey: Self.legacyCredentialsKey)
    }
}

// MARK: - Global Shared Instance

extension AWSCredentialsManager {
    static let shared = AWSCredentialsManager()
}
