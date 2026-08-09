import Foundation
import Security

// MARK: - AWS Credential Storage

protocol AWSCredentialsStorage {
    func loadCredentials() throws -> AWSCredentials?
    func saveCredentials(_ credentials: AWSCredentials) throws
    func deleteCredentials() throws
}

/// Keychain-backed storage for AWS Bedrock credentials.
final class AWSCredentialsHelper: AWSCredentialsStorage {

    // Deliberately distinct from the database-encryption Keychain service/account.
    static let keychainService = "com.bisonhealth.aws.credentials"
    static let keychainAccount = "aws-bedrock"
    // Computed rather than stored: the Security framework's accessibility constants are
    // immutable CFStrings, but CFString is not Sendable, so a stored static would be
    // rejected as global mutable state.
    private static var keychainAccessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    // MARK: - Credential Management

    func saveCredentials(_ credentials: AWSCredentials) throws {
        let validation = Self.validateCredentials(credentials)
        guard validation.isValid else {
            throw AWSCredentialsError.validationFailed(validation.issues)
        }

        let data = try JSONEncoder().encode(credentials)
        let query = Self.keychainIdentityQuery()
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.keychainAccessibility
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = Self.keychainAccessibility

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AWSCredentialsError.keychainError(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw AWSCredentialsError.keychainError(updateStatus)
        }

        // This message intentionally contains no credential material.
        AppLog.shared.networking("AWS credentials saved securely to Keychain")
    }

    func loadCredentials() throws -> AWSCredentials? {
        var query = Self.keychainIdentityQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw AWSCredentialsError.keychainError(status)
        }

        guard let data = result as? Data else {
            throw AWSCredentialsError.invalidData
        }

        do {
            return try JSONDecoder().decode(AWSCredentials.self, from: data)
        } catch {
            throw AWSCredentialsError.invalidData
        }
    }

    func deleteCredentials() throws {
        let status = SecItemDelete(Self.keychainIdentityQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AWSCredentialsError.keychainError(status)
        }

        // This message intentionally contains no credential material.
        AppLog.shared.networking("AWS credentials deleted from Keychain")
    }

    // MARK: - Validation

    static func validateCredentials(_ credentials: AWSCredentials) -> ValidationResult {
        var issues: [String] = []

        if credentials.accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Access key is required")
        }
        if credentials.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Secret key is required")
        }
        // The region is interpolated into the SDK's endpoint host, so its shape is
        // checked. Key formats are deliberately not checked: they vary across
        // long-lived, temporary (ASIA), and role-derived credentials.
        let trimmedRegion = credentials.region.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRegion.isEmpty {
            issues.append("Region is required")
        } else if trimmedRegion.range(of: #"^[a-z]{2}(-[a-z]+)+-[0-9]+$"#, options: .regularExpression) == nil {
            issues.append("Region format should be like 'us-east-1'")
        }
        if let sessionToken = credentials.sessionToken,
           sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Session token cannot be empty")
        }

        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }

    struct ValidationResult {
        let isValid: Bool
        let issues: [String]

        var errorMessage: String? {
            isValid ? nil : issues.joined(separator: "\n")
        }
    }

    // MARK: - Configuration Templates

    static let supportedRegions = [
        "us-east-1": "US East (N. Virginia)",
        "us-west-2": "US West (Oregon)",
        "eu-west-1": "Europe (Ireland)",
        "eu-central-1": "Europe (Frankfurt)",
        "ap-southeast-1": "Asia Pacific (Singapore)",
        "ap-northeast-1": "Asia Pacific (Tokyo)"
    ]

    static let commonModels = [
        "anthropic.claude-3-haiku-20240307-v1:0": "Claude 3 Haiku (Fast, Cost-effective)",
        "anthropic.claude-3-sonnet-20240229-v1:0": "Claude 3 Sonnet (Balanced)",
        "anthropic.claude-3-opus-20240229-v1:0": "Claude 3 Opus (Most Capable)",
        "anthropic.claude-3-5-sonnet-20240620-v1:0": "Claude 3.5 Sonnet (Latest)",
        "amazon.titan-text-premier-v1:0": "Amazon Titan Text Premier",
        "meta.llama3-70b-instruct-v1:0": "Meta Llama 3 70B",
        "cohere.command-r-plus-v1:0": "Cohere Command R+"
    ]

    // MARK: - Keychain Query

    private static func keychainIdentityQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}

// MARK: - AWS Credential Errors

enum AWSCredentialsError: LocalizedError, Equatable {
    case keychainError(OSStatus)
    case invalidData
    case validationFailed([String])
    case verificationFailed
    case legacyCredentialConflict
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .keychainError:
            return "Secure credential storage is unavailable."
        case .invalidData:
            return "The saved AWS credentials could not be read."
        case .validationFailed(let issues):
            return "Credential validation failed: \(issues.joined(separator: ", "))"
        case .verificationFailed:
            return "Secure credential storage could not be verified."
        case .legacyCredentialConflict:
            return "Secure and legacy AWS credentials do not match."
        case .storageUnavailable:
            return "Secure credential storage is unavailable."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .validationFailed:
            return "Please check the AWS credential fields."
        case .legacyCredentialConflict:
            return "Keep the credentials shown above, or enter the ones you want and save."
        default:
            return "Check app permissions and try again."
        }
    }
}
