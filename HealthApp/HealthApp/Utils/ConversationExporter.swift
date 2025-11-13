import Foundation
import UIKit
import PDFKit

// MARK: - Paper Size Configuration
enum PaperSize {
    case usLetter  // 8.5" x 11" (612 x 792 points)
    case a4        // 210mm x 297mm (595 x 842 points)

    var size: CGSize {
        switch self {
        case .usLetter:
            return CGSize(width: 612, height: 792)
        case .a4:
            return CGSize(width: 595, height: 842)
        }
    }

    /// Determines appropriate paper size based on user's locale
    static var `default`: PaperSize {
        let locale = Locale.current
        // Use A4 for most international locales, US Letter for US/Canada/Mexico
        let usLetterRegions = ["US", "CA", "MX"]
        if let regionCode = locale.region?.identifier,
           usLetterRegions.contains(regionCode) {
            return .usLetter
        }
        return .a4
    }
}

// MARK: - Conversation Exporter
@MainActor
class ConversationExporter: ObservableObject {

    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    @Published var lastError: Error?

    private let fileSystemManager: FileSystemManager
    private let paperSize: PaperSize

    // MARK: - Initialization
    init(fileSystemManager: FileSystemManager, paperSize: PaperSize = .default) {
        self.fileSystemManager = fileSystemManager
        self.paperSize = paperSize
    }

    // MARK: - Markdown Export
    func exportConversationAsMarkdown(_ conversation: ChatConversation) async throws -> URL {
        isExporting = true
        exportProgress = 0.0

        defer {
            isExporting = false
            exportProgress = 0.0
        }

        do {
            // Performance: Log warning for large conversations
            let messageCount = conversation.messages.count
            if messageCount > 100 {
                print("⚠️ Large conversation (\(messageCount) messages) - export may take time")
            }

            // Generate markdown content
            var markdown = "# \(conversation.title)\n\n"
            markdown += "**Created:** \(formatDate(conversation.createdAt))\n"
            markdown += "**Last Updated:** \(formatDate(conversation.updatedAt))\n"

            if !conversation.tags.isEmpty {
                markdown += "**Tags:** \(conversation.tags.joined(separator: ", "))\n"
            }

            markdown += "\n---\n\n"

            exportProgress = 0.2

            // Add messages
            let totalMessages = conversation.messages.count
            for (index, message) in conversation.messages.enumerated() {
                let roleEmoji: String
                let roleTitle: String

                switch message.role {
                case .user:
                    roleEmoji = "👤"
                    roleTitle = "You"
                case .assistant:
                    roleEmoji = "🤖"
                    roleTitle = "Doctor"
                case .system:
                    roleEmoji = "⚙️"
                    roleTitle = "System"
                }

                markdown += "## \(roleEmoji) \(roleTitle)\n"
                markdown += "*\(formatDate(message.timestamp))*\n\n"
                markdown += "\(message.content)\n\n"
                markdown += "---\n\n"

                exportProgress = 0.2 + (0.6 * Double(index + 1) / Double(totalMessages))
            }

            // Add metadata footer
            markdown += "\n\n---\n\n"
            markdown += "*Exported from BisonHealth AI*\n"
            markdown += "*Total Messages: \(totalMessages)*\n"
            markdown += "*Export Date: \(formatDate(Date()))*\n"

            exportProgress = 0.9

            // Convert to data
            guard let markdownData = markdown.data(using: .utf8) else {
                throw ConversationExportError.markdownGenerationFailed
            }

            // Generate filename
            let sanitizedTitle = sanitizeFileName(conversation.title)
            let timestamp = formatFileTimestamp(Date())
            let fileName = "\(sanitizedTitle)_\(timestamp)"

            // Save to exports directory
            let exportURL = try fileSystemManager.createExportFile(
                data: markdownData,
                fileName: fileName,
                fileType: .markdown
            )

            exportProgress = 1.0
            return exportURL

        } catch {
            lastError = error
            throw error
        }
    }

    // MARK: - PDF Export
    func exportConversationAsPDF(_ conversation: ChatConversation) async throws -> URL {
        isExporting = true
        exportProgress = 0.0

        defer {
            isExporting = false
            exportProgress = 0.0
        }

        do {
            // Performance: Log warning for large conversations
            let messageCount = conversation.messages.count
            if messageCount > 100 {
                print("⚠️ Large conversation (\(messageCount) messages) - export may take time")
            }

            // Create PDF document
            let pdfDocument = PDFDocument()
            var pageIndex = 0

            exportProgress = 0.1

            // Title Page
            let titlePage = createTitlePage(conversation: conversation)
            pdfDocument.insert(titlePage, at: pageIndex)
            pageIndex += 1

            exportProgress = 0.3

            // Message Pages
            let messagePages = try await createMessagePages(conversation: conversation)
            for page in messagePages {
                pdfDocument.insert(page, at: pageIndex)
                pageIndex += 1
                exportProgress = 0.3 + (0.5 * Double(pageIndex) / Double(messagePages.count + 1))
            }

            exportProgress = 0.9

            // Save PDF
            guard let pdfData = pdfDocument.dataRepresentation() else {
                throw ConversationExportError.pdfGenerationFailed
            }

            // Generate filename
            let sanitizedTitle = sanitizeFileName(conversation.title)
            let timestamp = formatFileTimestamp(Date())
            let fileName = "\(sanitizedTitle)_\(timestamp)"

            // Save to exports directory
            let exportURL = try fileSystemManager.createExportFile(
                data: pdfData,
                fileName: fileName,
                fileType: .pdf
            )

            exportProgress = 1.0
            return exportURL

        } catch {
            lastError = error
            throw error
        }
    }

    // MARK: - PDF Page Creation
    private func createTitlePage(conversation: ChatConversation) -> PDFPage {
        let pageSize = paperSize.size
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)

        let image = renderer.image { context in
            let ctx = context.cgContext

            // Background
            UIColor.white.setFill()
            ctx.fill(pageRect)

            var yPosition: CGFloat = 100

            // Title
            let titleFont = UIFont.systemFont(ofSize: 28, weight: .bold)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            let titleText = conversation.title
            let titleSize = titleText.size(withAttributes: titleAttributes)
            let titleRect = CGRect(
                x: (pageRect.width - titleSize.width) / 2,
                y: yPosition,
                width: titleSize.width,
                height: titleSize.height
            )
            titleText.draw(in: titleRect, withAttributes: titleAttributes)

            yPosition += titleSize.height + 40

            // Metadata
            let metadataFont = UIFont.systemFont(ofSize: 12)
            let metadataAttributes: [NSAttributedString.Key: Any] = [
                .font: metadataFont,
                .foregroundColor: UIColor.darkGray
            ]

            let metadata = [
                "Created: \(formatDate(conversation.createdAt))",
                "Last Updated: \(formatDate(conversation.updatedAt))",
                "Total Messages: \(conversation.messages.count)",
                "Tags: \(conversation.tags.isEmpty ? "None" : conversation.tags.joined(separator: ", "))"
            ]

            for line in metadata {
                let lineSize = line.size(withAttributes: metadataAttributes)
                let lineRect = CGRect(
                    x: 72,
                    y: yPosition,
                    width: pageRect.width - 144,
                    height: lineSize.height
                )
                line.draw(in: lineRect, withAttributes: metadataAttributes)
                yPosition += lineSize.height + 10
            }

            // Footer
            yPosition = pageRect.height - 100
            let footerFont = UIFont.systemFont(ofSize: 10, weight: .light)
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor.lightGray
            ]
            let footerText = "Exported from BisonHealth AI - \(formatDate(Date()))"
            let footerSize = footerText.size(withAttributes: footerAttributes)
            let footerRect = CGRect(
                x: (pageRect.width - footerSize.width) / 2,
                y: yPosition,
                width: footerSize.width,
                height: footerSize.height
            )
            footerText.draw(in: footerRect, withAttributes: footerAttributes)
        }

        guard let pdfPage = PDFPage(image: image) else {
            throw ConversationExportError.pdfGenerationFailed
        }
        return pdfPage
    }

    private func createMessagePages(conversation: ChatConversation) async throws -> [PDFPage] {
        let pageSize = paperSize.size
        let pageRect = CGRect(origin: .zero, size: pageSize)
        var pages: [PDFPage] = []

        let margin: CGFloat = 72
        let contentWidth = pageRect.width - (margin * 2)
        var currentYPosition: CGFloat = margin
        let maxYPosition = pageRect.height - margin

        var currentPageMessages: [(message: ChatMessage, height: CGFloat)] = []

        let totalMessages = conversation.messages.count
        let isLargeConversation = totalMessages > 50

        for (index, message) in conversation.messages.enumerated() {
            // Performance: Yield every 10 messages to keep UI responsive
            if index % 10 == 0 {
                await Task.yield()
            }

            // Performance: Update progress more frequently for large conversations
            if isLargeConversation {
                let messageProgress = 0.3 + (0.5 * Double(index) / Double(totalMessages))
                exportProgress = messageProgress
            }

            let messageHeight = calculateMessageHeight(message: message, width: contentWidth)

            // Check if we need a new page
            if currentYPosition + messageHeight > maxYPosition && !currentPageMessages.isEmpty {
                // Create page with current messages
                let page = try renderMessagesPage(
                    messages: currentPageMessages.map { $0.message },
                    pageRect: pageRect,
                    margin: margin
                )
                pages.append(page)

                // Reset for new page
                currentPageMessages = []
                currentYPosition = margin
            }

            currentPageMessages.append((message, messageHeight))
            currentYPosition += messageHeight + 20
        }

        // Create final page if there are remaining messages
        if !currentPageMessages.isEmpty {
            let page = try renderMessagesPage(
                messages: currentPageMessages.map { $0.message },
                pageRect: pageRect,
                margin: margin
            )
            pages.append(page)
        }

        return pages
    }

    private func renderMessagesPage(messages: [ChatMessage], pageRect: CGRect, margin: CGFloat) throws -> PDFPage {
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)

        let image = renderer.image { context in
            let ctx = context.cgContext

            // Background
            UIColor.white.setFill()
            ctx.fill(pageRect)

            var yPosition = margin

            for message in messages {
                // Role header
                let roleText: String
                let roleColor: UIColor

                switch message.role {
                case .user:
                    roleText = "👤 You"
                    roleColor = .systemBlue
                case .assistant:
                    roleText = "🤖 Doctor"
                    roleColor = .systemGreen
                case .system:
                    roleText = "⚙️ System"
                    roleColor = .systemGray
                }

                let roleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
                let roleAttributes: [NSAttributedString.Key: Any] = [
                    .font: roleFont,
                    .foregroundColor: roleColor
                ]

                let roleSize = roleText.size(withAttributes: roleAttributes)
                let roleRect = CGRect(x: margin, y: yPosition, width: roleSize.width, height: roleSize.height)
                roleText.draw(in: roleRect, withAttributes: roleAttributes)

                yPosition += roleSize.height + 5

                // Timestamp
                let timestampText = formatDate(message.timestamp)
                let timestampFont = UIFont.systemFont(ofSize: 10, weight: .light)
                let timestampAttributes: [NSAttributedString.Key: Any] = [
                    .font: timestampFont,
                    .foregroundColor: UIColor.gray
                ]
                let timestampSize = timestampText.size(withAttributes: timestampAttributes)
                let timestampRect = CGRect(x: margin, y: yPosition, width: timestampSize.width, height: timestampSize.height)
                timestampText.draw(in: timestampRect, withAttributes: timestampAttributes)

                yPosition += timestampSize.height + 8

                // Message content
                let contentFont = UIFont.systemFont(ofSize: 11)
                let contentAttributes: [NSAttributedString.Key: Any] = [
                    .font: contentFont,
                    .foregroundColor: UIColor.black
                ]

                let contentRect = CGRect(
                    x: margin,
                    y: yPosition,
                    width: pageRect.width - (margin * 2),
                    height: pageRect.height - yPosition - margin
                )

                let attributedContent = NSAttributedString(string: message.content, attributes: contentAttributes)
                attributedContent.draw(in: contentRect)

                let contentSize = message.content.boundingRect(
                    with: CGSize(width: pageRect.width - (margin * 2), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: contentAttributes,
                    context: nil
                ).size

                yPosition += contentSize.height + 20
            }
        }

        guard let pdfPage = PDFPage(image: image) else {
            throw ConversationExportError.pdfGenerationFailed
        }
        return pdfPage
    }

    private func calculateMessageHeight(message: ChatMessage, width: CGFloat) -> CGFloat {
        let roleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let timestampFont = UIFont.systemFont(ofSize: 10, weight: .light)
        let contentFont = UIFont.systemFont(ofSize: 11)

        let roleHeight: CGFloat = 20
        let timestampHeight: CGFloat = 15

        let contentAttributes: [NSAttributedString.Key: Any] = [.font: contentFont]
        let contentSize = message.content.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: contentAttributes,
            context: nil
        ).size

        return roleHeight + timestampHeight + contentSize.height + 20
    }

    // MARK: - Helper Methods
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatFileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Export Errors
enum ConversationExportError: LocalizedError {
    case markdownGenerationFailed
    case pdfGenerationFailed
    case invalidConversation

    var errorDescription: String? {
        switch self {
        case .markdownGenerationFailed:
            return "Failed to generate markdown document"
        case .pdfGenerationFailed:
            return "Failed to generate PDF document"
        case .invalidConversation:
            return "Invalid conversation data"
        }
    }
}
