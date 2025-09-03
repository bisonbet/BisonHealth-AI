import Foundation

// MARK: - Docling Client
@MainActor
class DoclingClient: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = DoclingClient(hostname: "localhost", port: 5001)
    
    @Published var isConnected = false
    @Published var connectionStatus: DoclingConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var processingJobs: [String: ProcessingJob] = [:]
    
    let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval = 60.0 // Longer timeout for document processing
    
    // Authentication properties
    private var apiKey: String?
    
    // MARK: - Initialization
    init(hostname: String, port: Int) {
        guard let url = URL(string: "http://\(hostname):\(port)") else {
            // Fallback to localhost if URL creation fails
            self.baseURL = URL(string: "http://localhost:\(port)")!
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 3
            self.session = URLSession(configuration: config)
            return
        }
        
        self.baseURL = url
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 3
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Configuration
    
    func setAPIKey(_ key: String?) {
        apiKey = key
    }
    
    // MARK: - Connection Management
    func testConnection() async throws -> Bool {
        connectionStatus = .connecting
        
        do {
            // Docling v1 API doesn't have a dedicated health endpoint
            // Use HEAD request to /v1/convert/file to test service availability
            let convertURL = baseURL.appendingPathComponent("v1/convert/file")
            var request = URLRequest(url: convertURL)
            request.httpMethod = "HEAD"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10.0 // Short timeout for health checks
            
            // Add authentication header if API key is configured
            if let apiKey = apiKey, !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            }
            
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoclingError.invalidResponse
            }
            
            // For HEAD request to /v1/convert/file:
            // - 405 (Method Not Allowed) means service is running but doesn't support HEAD
            // - 200 (OK) means service accepts HEAD requests
            // Both indicate the service is accessible and running
            let success = httpResponse.statusCode == 200 || httpResponse.statusCode == 405
            
            if success {
                connectionStatus = .connected
                isConnected = true
            } else {
                connectionStatus = .disconnected
                isConnected = false
                throw DoclingError.connectionFailed(httpResponse.statusCode)
            }
            
            return success
            
        } catch {
            connectionStatus = .disconnected
            isConnected = false
            lastError = error
            throw error
        }
    }
    
    // MARK: - Document Processing
    func processDocument(_ document: Data, type: DocumentType, options: ProcessingOptions = ProcessingOptions()) async throws -> ProcessedDocumentResult {
        guard isConnected else {
            throw DoclingError.notConnected
        }
        
        let processURL = baseURL.appendingPathComponent("v1/convert/source")
        var request = URLRequest(url: processURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add authentication headers when needed
        
        // Create v1 API request body
        let base64Document = document.base64EncodedString()
        let filename = "document.\(type.rawValue)"
        
        let requestBody = DoclingV1ConvertRequest(
            sources: [
                DoclingV1Source(
                    kind: "file",
                    base64String: base64Document,
                    filename: filename
                )
            ],
            options: options.toV1Options(),
            target: DoclingV1Target(kind: "json")
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        do {
            let startTime = Date()
            let (data, response) = try await session.data(for: request)
            let processingTime = Date().timeIntervalSince(startTime)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoclingError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw DoclingError.processingFailed(httpResponse.statusCode)
            }
            
            let processingResponse = try JSONDecoder().decode(DoclingProcessingResponse.self, from: data)
            
            return ProcessedDocumentResult(
                extractedText: processingResponse.extractedText,
                structuredData: processingResponse.structuredData,
                confidence: processingResponse.confidence,
                processingTime: processingTime,
                metadata: processingResponse.metadata
            )
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Async Processing
    func submitDocumentForProcessing(_ document: Data, type: DocumentType, options: ProcessingOptions = ProcessingOptions()) async throws -> String {
        guard isConnected else {
            throw DoclingError.notConnected
        }
        
        let submitURL = baseURL.appendingPathComponent("v1/convert/source")
        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create v1 API request body for async processing
        let base64Document = document.base64EncodedString()
        let filename = "document.\(type.rawValue)"
        
        let requestBody = DoclingV1ConvertRequest(
            sources: [
                DoclingV1Source(
                    kind: "file",
                    base64String: base64Document,
                    filename: filename
                )
            ],
            options: options.toV1Options(),
            target: DoclingV1Target(kind: "json")
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoclingError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw DoclingError.processingFailed(httpResponse.statusCode)
            }
            
            let submitResponse = try JSONDecoder().decode(DoclingSubmitResponse.self, from: data)
            
            // Track the processing job
            let job = ProcessingJob(
                id: submitResponse.jobId,
                status: .processing,
                submittedAt: Date()
            )
            processingJobs[submitResponse.jobId] = job
            
            return submitResponse.jobId
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    func getProcessingStatus(_ jobId: String) async throws -> DoclingProcessingStatus {
        guard isConnected else {
            throw DoclingError.notConnected
        }
        
        let statusURL = baseURL.appendingPathComponent("v1/status/\(jobId)")
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoclingError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 404 {
                    throw DoclingError.jobNotFound
                }
                throw DoclingError.requestFailed(httpResponse.statusCode)
            }
            
            let statusResponse = try JSONDecoder().decode(DoclingStatusResponse.self, from: data)
            
            // Update local job tracking
            if var job = processingJobs[jobId] {
                job.status = statusResponse.status
                job.progress = statusResponse.progress
                job.updatedAt = Date()
                processingJobs[jobId] = job
            }
            
            return statusResponse.status
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    func getProcessingResult(_ jobId: String) async throws -> ProcessedDocumentResult {
        guard isConnected else {
            throw DoclingError.notConnected
        }
        
        let resultURL = baseURL.appendingPathComponent("v1/result/\(jobId)")
        var request = URLRequest(url: resultURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoclingError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 404 {
                    throw DoclingError.jobNotFound
                }
                throw DoclingError.requestFailed(httpResponse.statusCode)
            }
            
            let resultResponse = try JSONDecoder().decode(DoclingProcessingResponse.self, from: data)
            
            // Update job status to completed
            if var job = processingJobs[jobId] {
                job.status = .completed
                job.completedAt = Date()
                processingJobs[jobId] = job
            }
            
            return ProcessedDocumentResult(
                extractedText: resultResponse.extractedText,
                structuredData: resultResponse.structuredData,
                confidence: resultResponse.confidence,
                processingTime: 0, // Not available for async processing
                metadata: resultResponse.metadata
            )
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Supported Formats
    func getSupportedFormats() async throws -> [String] {
        guard isConnected else {
            throw DoclingError.notConnected
        }
        
        let formatsURL = baseURL.appendingPathComponent("v1/formats")
        var request = URLRequest(url: formatsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoclingError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw DoclingError.requestFailed(httpResponse.statusCode)
            }
            
            let formatsResponse = try JSONDecoder().decode(DoclingFormatsResponse.self, from: data)
            return formatsResponse.supportedFormats
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Configuration
    func updateConfiguration(hostname: String, port: Int) {
        // Update base URL
        // Note: In a real implementation, you'd want to recreate the client
    }
    
    // TODO: Placeholder for future authentication implementation
    func authenticate(credentials: AuthCredentials) async throws {
        // Placeholder for future authentication implementation
        throw DoclingError.authenticationNotImplemented
    }
    
    // MARK: - Private Methods
    
    private func getMimeType(for documentType: DocumentType) -> String {
        switch documentType {
        case .pdf:
            return "application/pdf"
        case .doc:
            return "application/msword"
        case .docx:
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .jpeg, .jpg:
            return "image/jpeg"
        case .png:
            return "image/png"
        case .heic:
            return "image/heic"
        case .other:
            return "application/octet-stream"
        }
    }
}

// MARK: - Enums
enum DoclingConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

enum DoclingProcessingStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Data Models
struct ProcessingOptions: Codable {
    let extractText: Bool
    let extractStructuredData: Bool
    let extractImages: Bool
    let ocrEnabled: Bool
    let language: String?
    
    init(
        extractText: Bool = true,
        extractStructuredData: Bool = true,
        extractImages: Bool = false,
        ocrEnabled: Bool = true,
        language: String? = "en"
    ) {
        self.extractText = extractText
        self.extractStructuredData = extractStructuredData
        self.extractImages = extractImages
        self.ocrEnabled = ocrEnabled
        self.language = language
    }
    
    func toV1Options() -> DoclingV1Options {
        return DoclingV1Options(
            ocr: ocrEnabled,
            language: language
        )
    }
}

struct ProcessedDocumentResult {
    let extractedText: String
    let structuredData: [String: Any]
    let confidence: Double
    let processingTime: TimeInterval
    let metadata: [String: Any]?
    
    var healthDataItems: [HealthDataItem] {
        // Parse structured data to extract health information
        return parseHealthData(from: structuredData)
    }
    
    private func parseHealthData(from data: [String: Any]) -> [HealthDataItem] {
        var items: [HealthDataItem] = []
        
        // Look for common health data patterns
        if let bloodPressure = data["blood_pressure"] as? String {
            items.append(HealthDataItem(type: "Blood Pressure", value: bloodPressure))
        }
        
        if let heartRate = data["heart_rate"] as? String {
            items.append(HealthDataItem(type: "Heart Rate", value: heartRate))
        }
        
        if let medications = data["medications"] as? [String] {
            for medication in medications {
                items.append(HealthDataItem(type: "Medication", value: medication))
            }
        }
        
        // Add more parsing logic as needed
        
        return items
    }
}

struct HealthDataItem {
    let type: String
    let value: String
    let confidence: Double?
    
    init(type: String, value: String, confidence: Double? = nil) {
        self.type = type
        self.value = value
        self.confidence = confidence
    }
}

struct ProcessingJob {
    let id: String
    var status: DoclingProcessingStatus
    let submittedAt: Date
    var updatedAt: Date?
    var completedAt: Date?
    var progress: Double?
    
    init(id: String, status: DoclingProcessingStatus, submittedAt: Date) {
        self.id = id
        self.status = status
        self.submittedAt = submittedAt
    }
}

// MARK: - V1 API Models
struct DoclingV1ConvertRequest: Codable {
    let sources: [DoclingV1Source]
    let options: DoclingV1Options
    let target: DoclingV1Target
}

struct DoclingV1Source: Codable {
    let kind: String
    let base64String: String?
    let filename: String?
    let url: String?
    
    enum CodingKeys: String, CodingKey {
        case kind
        case base64String = "base64_string"
        case filename
        case url
    }
    
    init(kind: String, base64String: String? = nil, filename: String? = nil, url: String? = nil) {
        self.kind = kind
        self.base64String = base64String
        self.filename = filename
        self.url = url
    }
}

struct DoclingV1Options: Codable {
    let ocr: Bool?
    let language: String?
    
    init(ocr: Bool? = nil, language: String? = nil) {
        self.ocr = ocr
        self.language = language
    }
}

struct DoclingV1Target: Codable {
    let kind: String
    
    init(kind: String) {
        self.kind = kind
    }
}

// MARK: - API Response Models
struct DoclingProcessingResponse: Codable {
    let extractedText: String
    let structuredData: [String: AnyCodable]
    let confidence: Double
    let metadata: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case extractedText = "extracted_text"
        case structuredData = "structured_data"
        case confidence
        case metadata
    }
}

struct DoclingSubmitResponse: Codable {
    let jobId: String
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
    }
}

struct DoclingStatusResponse: Codable {
    let jobId: String
    let status: DoclingProcessingStatus
    let progress: Double?
    let estimatedTimeRemaining: Int?
    
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case progress
        case estimatedTimeRemaining = "estimated_time_remaining"
    }
}

struct DoclingFormatsResponse: Codable {
    let supportedFormats: [String]
    
    enum CodingKeys: String, CodingKey {
        case supportedFormats = "supported_formats"
    }
}

// MARK: - Helper for Any Codable
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Errors
enum DoclingError: LocalizedError {
    case notConnected
    case connectionFailed(Int)
    case requestFailed(Int)
    case processingFailed(Int)
    case invalidResponse
    case jobNotFound
    case unsupportedFormat
    case authenticationNotImplemented
    case networkError(Error)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Docling server"
        case .connectionFailed(let code):
            return "Connection failed with status code: \(code)"
        case .requestFailed(let code):
            return "Request failed with status code: \(code)"
        case .processingFailed(let code):
            return "Document processing failed with status code: \(code)"
        case .invalidResponse:
            return "Invalid response from server"
        case .jobNotFound:
            return "Processing job not found"
        case .unsupportedFormat:
            return "Unsupported document format"
        case .authenticationNotImplemented:
            return "Authentication not yet implemented"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notConnected:
            return "Check your server configuration and test the connection"
        case .connectionFailed, .requestFailed, .processingFailed:
            return "Verify the server is running and accessible"
        case .invalidResponse:
            return "Check if the server is running the correct version of Docling"
        case .jobNotFound:
            return "The processing job may have expired or been removed"
        case .unsupportedFormat:
            return "Try converting the document to a supported format"
        case .authenticationNotImplemented:
            return "Authentication will be available in a future update"
        case .networkError:
            return "Check your network connection and server availability"
        case .decodingError:
            return "This may be a server compatibility issue"
        }
    }
}