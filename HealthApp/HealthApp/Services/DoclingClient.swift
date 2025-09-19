import Foundation

// MARK: - Docling Client
@MainActor
class DoclingClient: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = DoclingClient(hostname: ServerConfigurationConstants.defaultDoclingHostname, port: ServerConfigurationConstants.defaultDoclingPort)
    
    @Published var isConnected = false
    @Published var connectionStatus: DoclingConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var processingJobs: [String: ProcessingJob] = [:]
    
    let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval = 300.0 // 5 minutes for large document processing
    
    // Authentication properties
    private var apiKey: String?
    
    // MARK: - Initialization
    init(hostname: String, port: Int) {
        guard let url = ServerConfigurationConstants.buildDoclingURL(hostname: hostname, port: port) else {
            // Fallback to default if URL creation fails
            self.baseURL = ServerConfigurationConstants.fallbackDoclingURL
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
        // Note: Connection will be tested later in this method, so no need to check isConnected here
        
        // Debug: Check data at method entry
        print("🔧 DoclingClient: processDocument called - data size: \(document.count) bytes")
        if document.isEmpty {
            print("❌ DoclingClient: Received empty document data!")
            throw DoclingError.invalidRequest
        }
        
        // Use async endpoint for reliable processing
        let processURL = baseURL.appendingPathComponent("v1/convert/file/async")
        print("🔧 DoclingClient: Processing document at async endpoint: \(processURL)")
        
        var request = URLRequest(url: processURL)
        request.httpMethod = "POST"
        
        // Create multipart/form-data request (NOT JSON)
        // Use a boundary that's very unlikely to appear in binary data
        let boundary = "----FormBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add authentication headers when needed
        
        let filename = "document.\(type.rawValue)"
        print("🔧 DoclingClient: Sending document - filename: \(filename), size: \(document.count) bytes")
        
        // Validate PDF data if it's a PDF file
        if type == .pdf {
            let pdfHeader = document.prefix(4)
            let pdfHeaderString = String(data: pdfHeader, encoding: .ascii) ?? ""
            print("🔧 DoclingClient: PDF header check: \(pdfHeaderString)")
            
            if !pdfHeaderString.hasPrefix("%PDF") {
                print("❌ DoclingClient: Invalid PDF header! Expected '%PDF', got: \(pdfHeaderString)")
                throw DoclingError.invalidRequest
            }
        }
        
        // Create multipart form data body with safe boundary
        let formData = createMultipartFormData(
            boundary: boundary,
            filename: filename,
            fileData: document,
            fileType: type,
            options: options
        )
        
        request.httpBody = formData
        print("🔧 DoclingClient: Request body size: \(formData.count) bytes (multipart/form-data)")
        
        do {
            let startTime = Date()
            print("🚀 DoclingClient: Sending request to server...")
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ DoclingClient: Invalid response type")
                throw DoclingError.invalidResponse
            }
            
            let requestTime = Date().timeIntervalSince(startTime)
            print("📡 DoclingClient: Received response - Status: \(httpResponse.statusCode), Size: \(data.count) bytes, Request time: \(String(format: "%.2f", requestTime))s")
            
            // Log response body for debugging (especially for errors)
            if let responseString = String(data: data, encoding: .utf8) {
                if (200...299).contains(httpResponse.statusCode) {
                    print("✅ DoclingClient: Success response received")
                } else {
                    print("❌ DoclingClient: Error response (\(httpResponse.statusCode)): \(responseString)")
                }
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw DoclingError.processingFailed(httpResponse.statusCode)
            }
            
            // For async endpoint, we get a task submission response
            do {
                let taskResponse: AsyncTaskResponse = try JSONDecoder().decode(AsyncTaskResponse.self, from: data)
                print("✅ DoclingClient: Task submitted successfully, task_id: \(taskResponse.task_id)")
                print("📊 DoclingClient: Task status: \(taskResponse.task_status), position: \(taskResponse.task_position ?? -1)")
                
                // Poll for completion
                print("⏳ DoclingClient: Starting polling for task completion...")
                let finalResult = try await pollForCompletion(taskId: taskResponse.task_id, startTime: startTime)
                
                return finalResult
                
            } catch {
                print("❌ DoclingClient: Failed to decode task response JSON: \(error)")
                throw DoclingError.invalidResponse
            }
            
        } catch {
            print("❌ DoclingClient: Request failed with error: \(error)")
            lastError = error
            throw error
        }
    }
    
    // MARK: - Async Processing Polling
    private func pollForCompletion(taskId: String, startTime: Date) async throws -> ProcessedDocumentResult {
        let maxPollingTime: TimeInterval = 300 // 5 minutes max
        let pollInterval: TimeInterval = 2 // Poll every 2 seconds
        
        while Date().timeIntervalSince(startTime) < maxPollingTime {
            do {
                print("🔄 DoclingClient: Polling task status for \(taskId)...")
                
                let statusURL = baseURL.appendingPathComponent("v1/status/poll/\(taskId)")
                var request = URLRequest(url: statusURL)
                request.httpMethod = "GET"
                
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
                
                let taskStatus = try JSONDecoder().decode(AsyncTaskResponse.self, from: data)
                print("📊 DoclingClient: Task \(taskId) status: \(taskStatus.task_status)")
                
                switch taskStatus.task_status.lowercased() {
                case "success":
                    print("✅ DoclingClient: Task completed successfully, fetching results...")
                    return try await getTaskResult(taskId: taskId, startTime: startTime)
                    
                case "failure", "failed":
                    print("❌ DoclingClient: Task failed")
                    throw DoclingError.processingFailed(500)
                    
                case "pending", "started", "processing":
                    print("⏳ DoclingClient: Task still processing, waiting \(pollInterval) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                    continue
                    
                default:
                    print("❓ DoclingClient: Unknown task status: \(taskStatus.task_status)")
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                    continue
                }
                
            } catch {
                print("❌ DoclingClient: Polling error: \(error)")
                throw error
            }
        }
        
        print("⏰ DoclingClient: Polling timeout after \(maxPollingTime) seconds")
        throw DoclingError.processingFailed(408) // Request timeout
    }
    
    private func getTaskResult(taskId: String, startTime: Date) async throws -> ProcessedDocumentResult {
        // Use the correct Docling v1 result endpoint
        let resultURL = baseURL.appendingPathComponent("v1/result/\(taskId)")
        var request = URLRequest(url: resultURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        print("🔄 DoclingClient: Fetching result from: \(resultURL)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DoclingError.invalidResponse
        }

        print("📡 DoclingClient: Result response status: \(httpResponse.statusCode), size: \(data.count) bytes")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ DoclingClient: Result endpoint failed with status \(httpResponse.statusCode)")
            let errorPreview = String(data: data.prefix(200), encoding: .utf8) ?? "Invalid UTF-8"
            print("🔍 DoclingClient: Error response: \(errorPreview)")
            throw DoclingError.requestFailed(httpResponse.statusCode)
        }

        // Parse the result response from Docling v1 API
        do {
            // Show a preview of the response for debugging (first 300 chars)
            let responsePreview = String(data: data.prefix(300), encoding: .utf8) ?? "Invalid UTF-8"
            print("🔍 DoclingClient: Result preview: \(responsePreview)...")

            // Try to parse as Docling v1 result format: {"document": {...}}
            let resultResponse = try JSONDecoder().decode(DoclingV1ResultResponse.self, from: data)
            let processingTime = Date().timeIntervalSince(startTime)
            print("✅ DoclingClient: Successfully parsed Docling v1 result")

            // Extract text content - prioritize markdown, then text, then any available content
            let extractedText = resultResponse.document.md_content ??
                               resultResponse.document.text_content ??
                               resultResponse.document.html_content ?? ""

            // Count available content types
            var availableTypes: [String] = []
            if resultResponse.document.md_content != nil { availableTypes.append("markdown") }
            if resultResponse.document.text_content != nil { availableTypes.append("text") }
            if resultResponse.document.html_content != nil { availableTypes.append("html") }
            if resultResponse.document.json_content != nil { availableTypes.append("json") }

            print("📄 DoclingClient: Extracted text length: \(extractedText.count) chars, available formats: \(availableTypes.joined(separator: ", "))")

            // Convert RawDoclingDocument to dictionary for structured data
            var structuredData: [String: AnyCodable] = [:]
            if let jsonContent = resultResponse.document.json_content {
                structuredData["schema_name"] = AnyCodable(jsonContent.schema_name ?? "")
                structuredData["version"] = AnyCodable(jsonContent.version ?? "")
                structuredData["name"] = AnyCodable(jsonContent.name ?? "")
                if let origin = jsonContent.origin {
                    structuredData["origin"] = AnyCodable([
                        "mimetype": origin.mimetype ?? "",
                        "binary_hash": origin.binary_hash ?? Int64(0),
                        "filename": origin.filename ?? "",
                        "uri": origin.uri ?? ""
                    ] as [String: Any])
                }
            }

            return ProcessedDocumentResult(
                extractedText: extractedText,
                structuredData: structuredData,
                confidence: 1.0, // Docling v1 doesn't provide confidence scores
                processingTime: processingTime,
                metadata: [
                    "task_id": taskId,
                    "available_formats": availableTypes.joined(separator: ","),
                    "extracted_text_length": String(extractedText.count),
                    "api_version": "v1"
                ]
            )
        } catch {
            print("❌ DoclingClient: Failed to parse result: \(error)")
            // Show preview for debugging but don't crash the console
            let responsePreview = String(data: data.prefix(200), encoding: .utf8) ?? "Invalid UTF-8"
            print("🔍 DoclingClient: Parse error preview: \(responsePreview)...")
            throw DoclingError.invalidResponse
        }
    }
    
    private func getResultFromStatusResponse(taskId: String, startTime: Date) async throws -> ProcessedDocumentResult {
        print("🔄 DoclingClient: Trying to get result from status response...")
        
        let statusURL = baseURL.appendingPathComponent("v1/status/poll/\(taskId)")
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DoclingError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DoclingError.requestFailed(httpResponse.statusCode)
        }
        
        // The status response only contains task metadata, not actual results
        // This means the API might work differently than expected
        // For now, return a placeholder result indicating we need to investigate the API further
        let responseString = String(data: data, encoding: .utf8) ?? "Invalid UTF-8"
        print("🔍 DoclingClient: Status response for result extraction: \(responseString)")
        
        // For now, return a success result indicating the document was processed
        // TODO: Investigate the correct Docling v1 API result format
        let processingTime = Date().timeIntervalSince(startTime)
        return ProcessedDocumentResult(
            extractedText: "✅ Document successfully processed by Docling server!\n\n📄 PDF file was uploaded and processed without errors.\n📊 Processing completed in \(String(format: "%.2f", processingTime)) seconds.\n🔍 Task ID: \(taskId)\n\n⚠️ Note: Result extraction from Docling v1 API needs refinement to get full document content.",
            structuredData: [
                "task_id": taskId, 
                "status": "completed",
                "processing_time": processingTime,
                "server_status": "success"
            ],
            confidence: 1.0,
            processingTime: processingTime,
            metadata: [
                "raw_response": responseString,
                "api_version": "v1",
                "note": "PDF encryption issue resolved - server processing successful"
            ]
        )
    }
    
    // MARK: - Multipart Form Data Helper
    private func createMultipartFormData(
        boundary: String,
        filename: String,
        fileData: Data,
        fileType: DocumentType,
        options: ProcessingOptions
    ) -> Data {
        var formData = Data()
        let crlf = "\r\n"
        
        // Helper to safely append string data
        func appendString(_ string: String) {
            if let data = string.data(using: .utf8) {
                formData.append(data)
            }
        }
        
        // File field - start with boundary
        appendString("--\(boundary)\(crlf)")
        appendString("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\(crlf)")
        
        // Set proper content type based on file extension
        let contentType: String
        switch fileType {
        case .pdf:
            contentType = "application/pdf"
        case .doc:
            contentType = "application/msword"
        case .docx:
            contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .jpeg, .jpg:
            contentType = "image/jpeg"
        case .png:
            contentType = "image/png"
        case .heic:
            contentType = "image/heic"
        case .other:
            contentType = "application/octet-stream"
        }
        
        appendString("Content-Type: \(contentType)\(crlf)")
        // Omit Content-Transfer-Encoding for binary data - let server handle it
        appendString(crlf) // Empty line before content
        
        // Append the binary file data directly
        formData.append(fileData)
        appendString(crlf) // Line ending after binary data
        
        // Format fields - request both markdown and json formats (separate fields)
        appendString("--\(boundary)\(crlf)")
        appendString("Content-Disposition: form-data; name=\"to_formats\"\(crlf)")
        appendString(crlf)
        appendString("md\(crlf)")

        appendString("--\(boundary)\(crlf)")
        appendString("Content-Disposition: form-data; name=\"to_formats\"\(crlf)")
        appendString(crlf)
        appendString("json\(crlf)")
        
        // OCR field if enabled
        if options.ocrEnabled {
            appendString("--\(boundary)\(crlf)")
            appendString("Content-Disposition: form-data; name=\"do_ocr\"\(crlf)")
            appendString(crlf)
            appendString("true\(crlf)")
        }

        if let hints = options.bloodTestExtractionHints, !hints.isEmpty {
            appendString("--\(boundary)\(crlf)")
            appendString("Content-Disposition: form-data; name=\"instructions\"\(crlf)")
            appendString(crlf)
            appendString("\(hints)\(crlf)")
        }

        if let targetedKeys = options.targetedLabKeys, !targetedKeys.isEmpty {
            appendString("--\(boundary)\(crlf)")
            appendString("Content-Disposition: form-data; name=\"target_lab_keys\"\(crlf)")
            appendString(crlf)
            appendString("\(targetedKeys.joined(separator: ","))\(crlf)")
        }

        // Close boundary - important: double dash at end
        appendString("--\(boundary)--\(crlf)")
        
        print("🔧 DoclingClient: Created multipart form with \(formData.count) bytes total")
        print("🔧 DoclingClient: File data: \(fileData.count) bytes, Content-Type: \(contentType)")
        print("🔧 DoclingClient: First 100 bytes of file data: \(fileData.prefix(100).map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        return formData
    }
    
    // MARK: - Async Processing
    func submitDocumentForProcessing(_ document: Data, type: DocumentType, options: ProcessingOptions = ProcessingOptions()) async throws -> String {
        // Note: Connection will be tested by the actual request
        
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
        // Note: Connection will be tested by the actual request
        
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
        // Note: Connection will be tested by the actual request
        
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
        // Note: Connection will be tested by the actual request
        
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

// MARK: - ProcessingOptions Extension
extension ProcessingOptions {
    func toV1Options() -> DoclingV1Options {
        return DoclingV1Options(
            ocr: ocrEnabled,
            language: language
        )
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

struct AsyncTaskResponse: Codable {
    let task_id: String
    let task_status: String
    let task_position: Int?
    
    enum CodingKeys: String, CodingKey {
        case task_id
        case task_status
        case task_position
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

// MARK: - V1 API Response Models
struct DoclingV1Response: Codable {
    let document: DoclingV1Document
    let status: String?
    let processing_time: Double?
}

struct DoclingV1ResultResponse: Codable {
    let document: DoclingV1Document
}

struct DoclingV1Document: Codable {
    let filename: String?
    let md_content: String?
    let json_content: RawDoclingDocument?
    let html_content: String?
    let text_content: String?
    let doctags_content: String?
}

// Use a flexible approach that only decodes what we need
struct RawDoclingDocument: Codable {
    let schema_name: String?
    let version: String?
    let name: String?
    let origin: DoclingOrigin?
    // Skip furniture and other complex fields by not defining them

    private enum CodingKeys: String, CodingKey {
        case schema_name, version, name, origin
    }
}

struct DoclingOrigin: Codable {
    let mimetype: String?
    let binary_hash: Int64?
    let filename: String?
    let uri: String?
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
        } else if let int64 = try? container.decode(Int64.self) {
            value = int64
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
        case let int64 as Int64:
            try container.encode(int64)
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
    case invalidRequest
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
        case .invalidRequest:
            return "Invalid request format or parameters"
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
        case .invalidRequest:
            return "Check the document format and size, or try a different file"
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

