import Foundation

// MARK: - Document Processing Models

struct ProcessedDocumentResult {
    let extractedText: String
    let structuredData: [String: Any]
    let confidence: Double
    let processingTime: TimeInterval
    let metadata: [String: Any]?
    /// Per-page OCR geometry (observations + tables) for the deterministic lab parser
    let pages: [NativeDocumentExtractor.PageText]?

    var healthDataItems: [HealthDataItem] {
        // Parse structured data to extract health information
        return parseHealthData(from: structuredData)
    }

    init(
        extractedText: String,
        structuredData: [String: Any] = [:],
        confidence: Double = 1.0,
        processingTime: TimeInterval = 0,
        metadata: [String: Any]? = nil,
        pages: [NativeDocumentExtractor.PageText]? = nil
    ) {
        self.extractedText = extractedText
        self.structuredData = structuredData
        self.confidence = confidence
        self.processingTime = processingTime
        self.metadata = metadata
        self.pages = pages
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

