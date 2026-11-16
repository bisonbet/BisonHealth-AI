//
//  HuggingFaceTokenStore.swift
//  HealthApp
//
//  Optional Hugging Face access token for on-device model downloads.
//

import Foundation
import HuggingFace

// MARK: - Hugging Face Token Store

/// Keeps the user's optional Hugging Face access token in the Keychain.
///
/// The public models this app downloads need no token. Without one, though, the Hub
/// counts every request against its anonymous rate limit (3,000 file resolves per five
/// minutes, shared by everyone behind the same IP address). A free account's token gets a
/// much higher limit.
///
/// The item is device-only (`Keychain`'s default protection class), so it never travels
/// through iCloud Keychain or a backup.
struct HuggingFaceTokenStore: Sendable {

    // MARK: - Properties

    static let keychainAccount = "huggingface_access_token"

    private let makeKeychain: @Sendable () -> KeychainStoring

    // MARK: - Initialization

    init(makeKeychain: @escaping @Sendable () -> KeychainStoring = { Keychain() }) {
        self.makeKeychain = makeKeychain
    }

    // MARK: - Public Methods

    /// The stored token, or nil when none is set or the Keychain cannot be read. A failed
    /// read falls back to anonymous downloads rather than failing them.
    func token() -> String? {
        guard let stored = try? makeKeychain().retrieveString(for: Self.keychainAccount) else {
            return nil
        }
        return Self.normalized(stored)
    }

    var hasToken: Bool { token() != nil }

    /// Saves the token, or removes the stored one when `token` is blank.
    func save(_ token: String) throws {
        guard let normalized = Self.normalized(token) else {
            try delete()
            return
        }
        try makeKeychain().store(string: normalized, for: Self.keychainAccount)
    }

    func delete() throws {
        try makeKeychain().delete(for: Self.keychainAccount)
    }

    /// Trims whitespace and newlines, which a paste often carries along, and treats an
    /// empty result as no token.
    static func normalized(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Asks the Hub who the token belongs to, returning the account name.
    ///
    /// - Throws: `HuggingFaceTokenError.rejected` when the Hub refuses the token, or the
    ///   underlying error when the Hub could not be reached.
    static func verify(_ token: String) async throws -> String {
        guard let normalized = normalized(token) else { throw HuggingFaceTokenError.rejected }
        let client = HubClient(host: HubClient.defaultHost, bearerToken: normalized, cache: nil)
        do {
            return try await client.whoami().name
        } catch let HTTPClientError.responseError(response, _) where response.statusCode == 401 {
            throw HuggingFaceTokenError.rejected
        }
    }
}

// MARK: - Errors

enum HuggingFaceTokenError: LocalizedError {
    case rejected

    var errorDescription: String? {
        "Hugging Face did not accept this token. Copy it again from huggingface.co/settings/tokens."
    }
}
