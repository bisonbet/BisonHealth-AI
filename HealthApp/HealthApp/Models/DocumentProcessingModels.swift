import Foundation

// MARK: - Document Processing Models

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

// MARK: - Processing Options
struct ProcessingOptions: Codable {
    let extractText: Bool
    let extractStructuredData: Bool
    let extractImages: Bool
    let ocrEnabled: Bool
    let language: String?
    let bloodTestExtractionHints: String?
    let targetedLabKeys: [String]?

    init(
        extractText: Bool = true,
        extractStructuredData: Bool = true,
        extractImages: Bool = false,
        ocrEnabled: Bool = true,
        language: String? = "en",
        bloodTestExtractionHints: String? = nil,
        targetedLabKeys: [String]? = nil
    ) {
        self.extractText = extractText
        self.extractStructuredData = extractStructuredData
        self.extractImages = extractImages
        self.ocrEnabled = ocrEnabled
        self.language = language
        self.bloodTestExtractionHints = bloodTestExtractionHints
        self.targetedLabKeys = targetedLabKeys
    }
}
