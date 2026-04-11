import Foundation
import Vision
import PDFKit
import UIKit
import CoreGraphics

// MARK: - Native Document Extractor
/// On-device document text extraction using Apple frameworks (PDFKit + Vision).
/// Replaces Docling for fully offline document processing.
///
/// Two-tier extraction strategy:
/// - Tier 1: PDFKit direct text extraction (instant, perfect for digital PDFs)
/// - Tier 2: Vision framework OCR (for scanned PDFs, images, camera captures)
///
/// After text extraction, spatial analysis reconstructs table/layout structure
/// from OCR bounding boxes — critical for lab reports with tabular data.
class NativeDocumentExtractor {

    // MARK: - Extraction Result

    /// Result of native document text extraction
    struct ExtractionResult {
        let text: String
        let method: ExtractionMethod
        let pageCount: Int
        let confidence: Double
        let perPageText: [PageText]

        /// Whether extraction produced meaningful text
        var isUsable: Bool {
            let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.count >= 50
        }
    }

    struct PageText {
        let pageNumber: Int
        let text: String
        let observations: [TextObservation]?
    }

    struct TextObservation {
        let text: String
        let confidence: Float
        let boundingBox: CGRect // Normalized coordinates (0-1), origin at bottom-left
    }

    enum ExtractionMethod: String {
        case pdfKit = "pdfkit_direct"
        case visionOCR = "vision_ocr"
        case hybrid = "hybrid" // PDFKit for some pages, OCR for others
    }

    // MARK: - Errors

    enum NativeExtractionError: LocalizedError {
        case fileNotFound(String)
        case unsupportedFileType(String)
        case pdfLoadFailed(String)
        case ocrFailed(String)
        case imageRenderFailed(Int)
        case emptyDocument
        case allPagesEmpty

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Document file not found at path: \(path)"
            case .unsupportedFileType(let type):
                return "Unsupported file type for native extraction: \(type)"
            case .pdfLoadFailed(let name):
                return "Failed to load PDF document: \(name)"
            case .ocrFailed(let detail):
                return "Vision OCR failed: \(detail)"
            case .imageRenderFailed(let page):
                return "Failed to render PDF page \(page) to image"
            case .emptyDocument:
                return "Document contains no pages"
            case .allPagesEmpty:
                return "No text could be extracted from any page"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .fileNotFound:
                return "Verify the document file exists and try re-importing."
            case .unsupportedFileType:
                return "Convert to PDF or a supported image format."
            case .pdfLoadFailed:
                return "The PDF may be corrupted or password-protected."
            case .ocrFailed:
                return "Try re-scanning the document with better lighting."
            case .imageRenderFailed:
                return "The PDF page may be too large or corrupted."
            case .emptyDocument:
                return "Select a document that contains content."
            case .allPagesEmpty:
                return "The document may be image-only. Try using Docling server for processing."
            }
        }
    }

    // MARK: - Configuration

    /// Minimum character count per page for PDFKit text to be considered "good"
    private let minTextPerPage = 20

    /// OCR recognition level (accurate is slower but much better for medical docs)
    private let recognitionLevel: VNRequestTextRecognitionLevel = .accurate

    /// Maximum pages to process (prevent runaway on huge documents)
    private let maxPages = 50

    /// DPI for rendering PDF pages to images for OCR
    private let renderDPI: CGFloat = 300.0

    // MARK: - Main Extraction Entry Point

    /// Extract text from a document file using the best available on-device method.
    ///
    /// Strategy:
    /// 1. For PDFs: Try PDFKit first (instant). If text is sparse, fall back to Vision OCR.
    /// 2. For images: Go directly to Vision OCR.
    /// 3. For DOCX: Extract via PDFKit if possible, otherwise OCR.
    ///
    /// - Parameters:
    ///   - url: File URL of the document
    ///   - fileType: The document's type
    /// - Returns: Extracted text with metadata about extraction method and quality
    func extractText(from url: URL, fileType: DocumentType) async throws -> ExtractionResult {
        AppLog.shared.documents("Starting on-device extraction from \(url.lastPathComponent) (type: \(fileType.rawValue))")

        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLog.shared.documents("File not found at path: \(url.path)", level: .error)
            throw NativeExtractionError.fileNotFound(url.path)
        }

        switch fileType {
        case .pdf:
            return try await extractFromPDF(at: url)
        case .jpeg, .jpg, .png, .heic:
            return try await extractFromImage(at: url)
        case .doc, .docx:
            // DOCX can sometimes be loaded via PDFKit; if not, try image conversion
            return try await extractFromPDF(at: url)
        case .other:
            throw NativeExtractionError.unsupportedFileType(fileType.rawValue)
        }
    }

    /// Extract text from raw document data (e.g., decrypted data from FileSystemManager).
    ///
    /// - Parameters:
    ///   - data: Raw document bytes
    ///   - fileType: The document's type
    ///   - fileName: Original filename (for logging)
    /// - Returns: Extracted text with metadata
    func extractText(from data: Data, fileType: DocumentType, fileName: String) async throws -> ExtractionResult {
        AppLog.shared.documents("Starting on-device extraction from data (\(data.count) bytes, type: \(fileType.rawValue), file: \(fileName))")

        guard !data.isEmpty else {
            AppLog.shared.documents("Document data is empty for file: \(fileName)", level: .error)
            throw NativeExtractionError.emptyDocument
        }

        switch fileType {
        case .pdf:
            return try await extractFromPDFData(data, fileName: fileName)
        case .jpeg, .jpg, .png, .heic:
            return try await extractFromImageData(data, fileName: fileName)
        case .doc, .docx:
            return try await extractFromPDFData(data, fileName: fileName)
        case .other:
            throw NativeExtractionError.unsupportedFileType(fileType.rawValue)
        }
    }

    // MARK: - PDF Extraction

    private func extractFromPDF(at url: URL) async throws -> ExtractionResult {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw NativeExtractionError.pdfLoadFailed(url.lastPathComponent)
        }
        return try await extractFromPDFDocument(pdfDocument, sourceName: url.lastPathComponent)
    }

    private func extractFromPDFData(_ data: Data, fileName: String) async throws -> ExtractionResult {
        guard let pdfDocument = PDFDocument(data: data) else {
            throw NativeExtractionError.pdfLoadFailed(fileName)
        }
        return try await extractFromPDFDocument(pdfDocument, sourceName: fileName)
    }

    private func extractFromPDFDocument(_ pdfDocument: PDFDocument, sourceName: String) async throws -> ExtractionResult {
        let pageCount = min(pdfDocument.pageCount, maxPages)
        AppLog.shared.documents("PDF '\(sourceName)' has \(pdfDocument.pageCount) pages (processing \(pageCount))")

        guard pageCount > 0 else {
            throw NativeExtractionError.emptyDocument
        }

        // Tier 1: Try PDFKit direct text extraction
        var pdfKitPages: [PageText] = []
        var pagesWithGoodText = 0
        var pagesNeedingOCR: [Int] = []

        for i in 0..<pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            let pageText = page.string ?? ""
            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.count >= minTextPerPage {
                pdfKitPages.append(PageText(pageNumber: i + 1, text: trimmed, observations: nil))
                pagesWithGoodText += 1
            } else {
                pdfKitPages.append(PageText(pageNumber: i + 1, text: trimmed, observations: nil))
                pagesNeedingOCR.append(i)
            }
        }

        AppLog.shared.documents("PDFKit Tier 1: extracted usable text from \(pagesWithGoodText)/\(pageCount) pages")

        // If PDFKit got good text from all pages, we're done
        if pagesNeedingOCR.isEmpty {
            let fullText = pdfKitPages.map { $0.text }.joined(separator: "\n\n--- Page Break ---\n\n")
            AppLog.shared.documents("PDFKit extraction complete — \(fullText.count) chars, all pages had embedded text")

            return ExtractionResult(
                text: fullText,
                method: .pdfKit,
                pageCount: pageCount,
                confidence: 0.95,
                perPageText: pdfKitPages
            )
        }

        // Tier 2: OCR pages that need it
        AppLog.shared.documents("Vision OCR Tier 2: running OCR on \(pagesNeedingOCR.count) pages that lack embedded text")
        var finalPages = pdfKitPages
        var ocrPageCount = 0

        for pageIndex in pagesNeedingOCR {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            do {
                let cgImage = try renderPDFPageToImage(page)
                let ocrResult = try await performOCR(on: cgImage)

                let reconstructedText = reconstructTextWithLayout(from: ocrResult.observations, pageSize: page.bounds(for: .mediaBox).size)

                if !reconstructedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finalPages[pageIndex] = PageText(
                        pageNumber: pageIndex + 1,
                        text: reconstructedText,
                        observations: ocrResult.observations
                    )
                    ocrPageCount += 1
                }
            } catch {
                AppLog.shared.documents("Vision OCR failed for page \(pageIndex + 1): \(error.localizedDescription)", level: .warning)
                // Keep whatever PDFKit got (possibly empty)
            }
        }

        let method: ExtractionMethod = pagesWithGoodText > 0 ? .hybrid : .visionOCR
        let avgConfidence = pagesWithGoodText > 0 ? 0.90 : 0.85
        let fullText = finalPages.map { $0.text }.joined(separator: "\n\n--- Page Break ---\n\n")

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLog.shared.documents("All pages empty after extraction — document may be image-only or corrupted", level: .error)
            throw NativeExtractionError.allPagesEmpty
        }

        AppLog.shared.documents("Extraction complete — method: \(method.rawValue), \(fullText.count) chars, \(ocrPageCount) OCR'd pages, \(pagesWithGoodText) PDFKit pages")

        return ExtractionResult(
            text: fullText,
            method: method,
            pageCount: pageCount,
            confidence: avgConfidence,
            perPageText: finalPages
        )
    }

    // MARK: - Image Extraction

    private func extractFromImage(at url: URL) async throws -> ExtractionResult {
        guard let imageData = try? Data(contentsOf: url) else {
            throw NativeExtractionError.fileNotFound(url.path)
        }
        return try await extractFromImageData(imageData, fileName: url.lastPathComponent)
    }

    private func extractFromImageData(_ data: Data, fileName: String) async throws -> ExtractionResult {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            AppLog.shared.documents("Could not create UIImage/CGImage from data (\(data.count) bytes) for \(fileName)", level: .error)
            throw NativeExtractionError.ocrFailed("Could not create image from data")
        }

        AppLog.shared.documents("Processing image \(fileName) (\(cgImage.width)x\(cgImage.height) px)")

        let ocrResult = try await performOCR(on: cgImage)
        let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let reconstructedText = reconstructTextWithLayout(from: ocrResult.observations, pageSize: imageSize)

        guard !reconstructedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLog.shared.documents("No text extracted from image \(fileName)", level: .error)
            throw NativeExtractionError.allPagesEmpty
        }

        AppLog.shared.documents("Image OCR complete — \(reconstructedText.count) chars, avg confidence: \(String(format: "%.0f", ocrResult.averageConfidence * 100))%")

        let pageText = PageText(
            pageNumber: 1,
            text: reconstructedText,
            observations: ocrResult.observations
        )

        return ExtractionResult(
            text: reconstructedText,
            method: .visionOCR,
            pageCount: 1,
            confidence: Double(ocrResult.averageConfidence),
            perPageText: [pageText]
        )
    }

    // MARK: - Vision OCR

    private struct OCRResult {
        let observations: [TextObservation]
        let averageConfidence: Float
    }

    private func performOCR(on cgImage: CGImage) async throws -> OCRResult {
        AppLog.shared.documents("Performing Vision OCR on image (\(cgImage.width)x\(cgImage.height) px), recognition level: accurate", level: .debug)
        let ocrResult: OCRResult = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: NativeExtractionError.ocrFailed(error.localizedDescription))
                    return
                }

                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: NativeExtractionError.ocrFailed("No text observations returned"))
                    return
                }

                var observations: [TextObservation] = []
                var totalConfidence: Float = 0

                for observation in results {
                    guard let candidate = observation.topCandidates(1).first else { continue }

                    observations.append(TextObservation(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    ))
                    totalConfidence += candidate.confidence
                }

                let avgConfidence = observations.isEmpty ? 0 : totalConfidence / Float(observations.count)

                continuation.resume(returning: OCRResult(
                    observations: observations,
                    averageConfidence: avgConfidence
                ))
            }

            request.recognitionLevel = self.recognitionLevel
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            // Use revision 3 for best accuracy on iOS 17+
            if #available(iOS 17.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: NativeExtractionError.ocrFailed(error.localizedDescription))
            }
        }
        return ocrResult
    }

    // MARK: - PDF Page Rendering

    private func renderPDFPageToImage(_ page: PDFPage) throws -> CGImage {
        let mediaBox = page.bounds(for: .mediaBox)

        // Scale to target DPI (PDF default is 72 DPI)
        let scale = renderDPI / 72.0
        let width = Int(mediaBox.width * scale)
        let height = Int(mediaBox.height * scale)

        guard width > 0, height > 0 else {
            throw NativeExtractionError.imageRenderFailed(page.document?.index(for: page) ?? -1)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NativeExtractionError.imageRenderFailed(page.document?.index(for: page) ?? -1)
        }

        // White background
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale and render the PDF page
        context.scaleBy(x: scale, y: scale)

        // PDFKit draws in Quartz coordinates, so translate to match
        context.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)

        // Draw the PDF page
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else {
            throw NativeExtractionError.imageRenderFailed(page.document?.index(for: page) ?? -1)
        }

        return cgImage
    }

    // MARK: - Spatial Text Reconstruction

    /// Reconstruct text with layout awareness from OCR observations.
    ///
    /// This is critical for lab reports where values must align with their labels.
    /// Groups observations into rows by Y-coordinate proximity, then sorts
    /// left-to-right within each row, with tab separation for columnar alignment.
    ///
    /// - Parameters:
    ///   - observations: Text observations with bounding boxes
    ///   - pageSize: Original page dimensions for coordinate scaling
    /// - Returns: Reconstructed text preserving tabular layout
    func reconstructTextWithLayout(from observations: [TextObservation], pageSize: CGSize) -> String {
        guard !observations.isEmpty else {
            AppLog.shared.documents("No observations to reconstruct", level: .debug)
            return ""
        }
        AppLog.shared.documents("Reconstructing layout from \(observations.count) text observations (page: \(Int(pageSize.width))x\(Int(pageSize.height)))", level: .debug)

        // Vision coordinates: origin at bottom-left, normalized 0-1
        // Sort by Y descending (top of page first), then X ascending (left to right)

        // Step 1: Group observations into rows based on Y-coordinate proximity
        let rowThreshold: CGFloat = 0.008 // ~0.8% of page height groups into same row

        struct Row {
            var observations: [TextObservation]
            var avgY: CGFloat
        }

        var rows: [Row] = []

        // Sort all observations top-to-bottom first
        let sorted = observations.sorted { a, b in
            // Higher Y = higher on page in Vision coordinates
            a.boundingBox.midY > b.boundingBox.midY
        }

        for obs in sorted {
            let obsY = obs.boundingBox.midY

            // Find an existing row close enough in Y
            if let rowIndex = rows.firstIndex(where: { abs($0.avgY - obsY) < rowThreshold }) {
                rows[rowIndex].observations.append(obs)
                // Update running average Y
                let count = CGFloat(rows[rowIndex].observations.count)
                rows[rowIndex].avgY = (rows[rowIndex].avgY * (count - 1) + obsY) / count
            } else {
                rows.append(Row(observations: [obs], avgY: obsY))
            }
        }

        // Step 2: Sort rows top-to-bottom, and within each row sort left-to-right
        rows.sort { $0.avgY > $1.avgY }

        // Step 3: Build text with tab separators for columnar data
        var lines: [String] = []

        for row in rows {
            let sortedObs = row.observations.sorted { $0.boundingBox.minX < $1.boundingBox.minX }

            // Detect column gaps: if horizontal gap between two observations is large,
            // insert a tab to preserve table structure
            var lineComponents: [String] = []
            var previousMaxX: CGFloat = 0

            for (index, obs) in sortedObs.enumerated() {
                if index > 0 {
                    let gap = obs.boundingBox.minX - previousMaxX
                    if gap > 0.03 { // Gap > 3% of page width suggests column separation
                        lineComponents.append("\t")
                    } else {
                        lineComponents.append(" ")
                    }
                }
                lineComponents.append(obs.text)
                previousMaxX = obs.boundingBox.maxX
            }

            let line = lineComponents.joined()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }

        let result = lines.joined(separator: "\n")
        AppLog.shared.documents("Layout reconstruction complete — \(rows.count) rows, \(lines.count) non-empty lines, \(result.count) chars", level: .debug)
        return result
    }
}
