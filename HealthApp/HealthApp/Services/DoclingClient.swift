import Foundation

// MARK: - Docling Client
@MainActor
class DoclingClient: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = DoclingClient(hostname: "localhost", port: 8080)
    
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var processingJobs: [String: ProcessingJob] = [:]
    
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval = 60.0 // Longer timeout for document processing
    
    // TODO: Add authentication properties when needed
    // private var apiKey: String?
    // private var authToken: String?
    
    // MARK: - Initialization
    init(hostname: String, port: Int) {
        self.baseURL = URL(string: "http://\(hostname):\(port)")!
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 3
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Connection Management
    func testConnection() async throws -> Bool {
        connectionStatus = .connecting
        
        do {
            let healthURL = baseURL.appendingPathComponent("health")
            var request = URLRequest(url: healthURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // TODO: Add authentication headers when needed
            // if let apiKey = apiKey {
            //     request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            // }
            
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoclingError.invalidResponse
            }
            
            let success = (200...299).contains(httpResponse.statusCode)
            
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
        
        let processURL = baseURL.appendingPathComponent("api/v1/process")
        var request = URLRequest(url: processURL)
        request.httpMethod = "POST"
        
        // TODO: Add authentication headers when needed
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let httpBody = createMultipartBody(
            document: document,
            type: type,
            options: options,
            boundary: boundary
        )
        request.httpBody = httpBody
        
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
        
        let submitURL = baseURL.appendingPathComponent("api/v1/submit")
        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let httpBody = createMultipartBody(
            document: document,
            type: type,
            options: options,
            boundary: boundary
        )
        request.httpBody = httpBody
        
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
    
    func getProcessingStatus(_ jobId: String) async throws -> ProcessingStatus {
        guard isConnected else {
            throw DoclingError.notConnected
        }
        
        let statusURL = baseURL.appendingPathComponent("api/v1/status/\(jobId)")
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
        
        let resultURL = baseURL.appendingPathComponent("api/v1/result/\(jobId)")
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
        
        let formatsURL = baseURL.appendingPathComponent("api/v1/formats")
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
    private func createMultipartBody(document: Data, type: DocumentType, options: ProcessingOptions, boundary: String) -> Data {
        var body = Data()
        
        // Add document file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"document.\(type.rawValue)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(getMimeType(for: type))\r\n\r\n".data(using: .utf8)!)
        body.append(document)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add processing options
        if let optionsData = try? JSONEncoder().encode(options) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"options\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(optionsData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
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
    var status: ProcessingStatus
    let submittedAt: Date
    var updatedAt: Date?
    var completedAt: Date?
    var progress: Double?
    
    init(id: String, status: ProcessingStatus, submittedAt: Date) {
        self.id = id
        self.status = status
        self.submittedAt = submittedAt
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
    let status: ProcessingStatus
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