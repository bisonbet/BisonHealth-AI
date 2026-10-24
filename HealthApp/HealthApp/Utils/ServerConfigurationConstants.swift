import Foundation

// MARK: - Server Configuration Constants
struct ServerConfigurationConstants {

    // MARK: - Default Server Settings
    static let defaultOpenAICompatibleBaseURL = "http://localhost:4000"
    static let defaultOpenAICompatibleAPIKey = ""

    /// Reply budget used when the user has not set one. Named here because both the client
    /// and the context budget need it, and two copies of the number would drift.
    static let defaultOpenAICompatibleMaxTokens = 2048
}
