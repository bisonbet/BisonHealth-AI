import Foundation

// MARK: - Server Configuration Constants
struct ServerConfigurationConstants {
    
    // MARK: - Default Server Settings
    static let defaultOllamaHostname = "localhost"
    static let defaultOllamaPort = 11434

    static let defaultDoclingHostname = "localhost"
    static let defaultDoclingPort = 5001

    static let defaultOpenAICompatibleBaseURL = "http://localhost:4000"
    static let defaultOpenAICompatibleAPIKey = ""
    
    // MARK: - URL Construction Helpers
    static func buildOllamaURL(hostname: String, port: Int) -> URL? {
        return URL(string: "http://\(hostname):\(port)")
    }
    
    static func buildDoclingURL(hostname: String, port: Int) -> URL? {
        return URL(string: "http://\(hostname):\(port)")
    }
    
    // MARK: - Fallback URLs (for error cases)
    static var fallbackOllamaURL: URL {
        return URL(string: "http://\(defaultOllamaHostname):\(defaultOllamaPort)")!
    }
    
    static var fallbackDoclingURL: URL {
        return URL(string: "http://\(defaultDoclingHostname):\(defaultDoclingPort)")!
    }
    
    // MARK: - Error Messages
    static func ollamaConnectionErrorMessage(hostname: String, port: Int) -> String {
        return "Check if the Ollama server is running on \(hostname):\(port)"
    }
    
    static func doclingConnectionErrorMessage(hostname: String, port: Int) -> String {
        return "Check if the Docling server is running on \(hostname):\(port)"
    }
    
    // MARK: - Default Server Configurations
    static var defaultOllamaConfig: ServerConfiguration {
        return ServerConfiguration(hostname: defaultOllamaHostname, port: defaultOllamaPort)
    }
    
    static var defaultDoclingConfig: ServerConfiguration {
        return ServerConfiguration(hostname: defaultDoclingHostname, port: defaultDoclingPort)
    }
}
