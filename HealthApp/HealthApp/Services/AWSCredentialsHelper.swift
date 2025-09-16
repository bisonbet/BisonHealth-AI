import Foundation
import Security

// MARK: - AWS Credentials Helper
class AWSCredentialsHelper {

    private static let keychainService = "com.bisonhealth.aws.credentials"

    // MARK: - Credential Storage
    struct AWSCredentials {
        let accessKey: String
        let secretKey: String
        let sessionToken: String?
        let region: String

        init(accessKey: String, secretKey: String, sessionToken: String? = nil, region: String = "us-east-1") {
            self.accessKey = accessKey
            self.secretKey = secretKey
            self.sessionToken = sessionToken
            self.region = region
        }

        // Format for AIProviderConfig.apiKey
        var formattedForConfig: String {
            if let sessionToken = sessionToken {
                return "\(accessKey):\(secretKey):\(sessionToken)"
            } else {
                return "\(accessKey):\(secretKey)"
            }
        }
    }

    // MARK: - Credential Management
    static func saveCredentials(_ credentials: AWSCredentials) throws {
        let data = try JSONEncoder().encode(CredentialData(
            accessKey: credentials.accessKey,
            secretKey: credentials.secretKey,
            sessionToken: credentials.sessionToken,
            region: credentials.region
        ))

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "aws-bedrock",
            kSecValueData as String: data
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AWSCredentialsError.keychainError(status)
        }

        print("✅ AWSCredentialsHelper: Credentials saved securely to Keychain")
    }

    static func loadCredentials() throws -> AWSCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "aws-bedrock",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

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

        let credentialData = try JSONDecoder().decode(CredentialData.self, from: data)

        return AWSCredentials(
            accessKey: credentialData.accessKey,
            secretKey: credentialData.secretKey,
            sessionToken: credentialData.sessionToken,
            region: credentialData.region
        )
    }

    static func deleteCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "aws-bedrock"
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AWSCredentialsError.keychainError(status)
        }

        print("✅ AWSCredentialsHelper: Credentials deleted from Keychain")
    }

    // MARK: - Validation
    static func validateCredentials(_ credentials: AWSCredentials) -> ValidationResult {
        var issues: [String] = []

        // Validate access key format (typically 20 characters starting with 'AKIA')
        if credentials.accessKey.isEmpty {
            issues.append("Access key is required")
        } else if credentials.accessKey.count < 16 {
            issues.append("Access key appears to be too short")
        } else if !credentials.accessKey.allSatisfy({ $0.isUppercase || $0.isNumber }) {
            issues.append("Access key should only contain uppercase letters and numbers")
        }

        // Validate secret key format (typically 40 characters)
        if credentials.secretKey.isEmpty {
            issues.append("Secret key is required")
        } else if credentials.secretKey.count < 32 {
            issues.append("Secret key appears to be too short")
        }

        // Validate region format
        if credentials.region.isEmpty {
            issues.append("Region is required")
        } else if !credentials.region.matches(regex: "^[a-z]{2}-[a-z]+-[0-9]+$") {
            issues.append("Region format should be like 'us-east-1'")
        }

        return ValidationResult(
            isValid: issues.isEmpty,
            issues: issues
        )
    }

    struct ValidationResult {
        let isValid: Bool
        let issues: [String]

        var errorMessage: String? {
            return isValid ? nil : issues.joined(separator: "\n")
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
}

// MARK: - Private Types
private struct CredentialData: Codable {
    let accessKey: String
    let secretKey: String
    let sessionToken: String?
    let region: String
}

// MARK: - AWS Credentials Errors
enum AWSCredentialsError: LocalizedError {
    case keychainError(OSStatus)
    case invalidData
    case validationFailed([String])

    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Invalid credential data format"
        case .validationFailed(let issues):
            return "Credential validation failed: \(issues.joined(separator: ", "))"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .keychainError:
            return "Check app permissions and try again"
        case .invalidData:
            return "Re-enter your AWS credentials"
        case .validationFailed:
            return "Please check your AWS credential format"
        }
    }
}

// MARK: - String Extension for Regex
private extension String {
    func matches(regex: String) -> Bool {
        return range(of: regex, options: .regularExpression) != nil
    }
}