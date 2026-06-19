import Foundation

// MARK: - Appointment Prep Status
/// Lifecycle of an appointment-prep report.
enum PrepStatus: String, Codable, CaseIterable {
    case draft
    case generating
    case complete

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .generating: return "Generating"
        case .complete: return "Complete"
        }
    }
}

// MARK: - Appointment Prep
/// A saved "prepare for doctor appointment" session.
///
/// The user enters this visit's symptoms/notes (and optionally edits the
/// auto-filled medication list); the app runs a three-call LLM workflow to
/// produce a `timeline`, `questions`, and `relevantInfo` report that can be
/// reviewed, edited, and exported before the appointment.
///
/// Ported from the Python `medical-appt-prep` tool, enhanced to pull the
/// user's existing health record into the LLM context.
struct AppointmentPrep: Identifiable, Codable, Equatable, Hashable {
    let id: UUID

    // MARK: User-Facing Metadata
    var title: String
    var appointmentDate: Date?
    var providerName: String?

    // MARK: Inputs
    /// Free-form description of symptoms/concerns for this visit (required, min 10 chars).
    var symptoms: String
    /// Optional context (stress, sleep changes, recent travel, diet, triggers).
    var notes: String
    /// Current medications/supplements, pre-filled from the health record and editable.
    var medications: String

    // MARK: Generated Output
    var timeline: String
    var questions: String
    var relevantInfo: String

    // MARK: Generation Context
    /// Which health-data types were fed into the LLM context when generating.
    var includedHealthDataTypes: Set<HealthDataType>
    var status: PrepStatus

    // MARK: Timestamps
    let createdAt: Date
    var lastModified: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        appointmentDate: Date? = nil,
        providerName: String? = nil,
        symptoms: String = "",
        notes: String = "",
        medications: String = "",
        timeline: String = "",
        questions: String = "",
        relevantInfo: String = "",
        includedHealthDataTypes: Set<HealthDataType> = [.personalInfo],
        status: PrepStatus = .draft,
        createdAt: Date = Date(),
        lastModified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.appointmentDate = appointmentDate
        self.providerName = providerName
        self.symptoms = symptoms
        self.notes = notes
        self.medications = medications
        self.timeline = timeline
        self.questions = questions
        self.relevantInfo = relevantInfo
        self.includedHealthDataTypes = includedHealthDataTypes
        self.status = status
        self.createdAt = createdAt
        self.lastModified = lastModified
    }

    // Custom decoding so older/partial records (or future fields) decode safely.
    private enum CodingKeys: String, CodingKey {
        case id, title, appointmentDate, providerName
        case symptoms, notes, medications
        case timeline, questions, relevantInfo
        case includedHealthDataTypes, status
        case createdAt, lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        appointmentDate = try container.decodeIfPresent(Date.self, forKey: .appointmentDate)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        symptoms = try container.decodeIfPresent(String.self, forKey: .symptoms) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        medications = try container.decodeIfPresent(String.self, forKey: .medications) ?? ""
        timeline = try container.decodeIfPresent(String.self, forKey: .timeline) ?? ""
        questions = try container.decodeIfPresent(String.self, forKey: .questions) ?? ""
        relevantInfo = try container.decodeIfPresent(String.self, forKey: .relevantInfo) ?? ""
        let types = try container.decodeIfPresent([HealthDataType].self, forKey: .includedHealthDataTypes) ?? [.personalInfo]
        includedHealthDataTypes = Set(types)
        status = try container.decodeIfPresent(PrepStatus.self, forKey: .status) ?? .draft
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(appointmentDate, forKey: .appointmentDate)
        try container.encodeIfPresent(providerName, forKey: .providerName)
        try container.encode(symptoms, forKey: .symptoms)
        try container.encode(notes, forKey: .notes)
        try container.encode(medications, forKey: .medications)
        try container.encode(timeline, forKey: .timeline)
        try container.encode(questions, forKey: .questions)
        try container.encode(relevantInfo, forKey: .relevantInfo)
        try container.encode(Array(includedHealthDataTypes), forKey: .includedHealthDataTypes)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
    }
}

// MARK: - Convenience
extension AppointmentPrep {
    mutating func clearGeneratedContent() {
        timeline = ""
        questions = ""
        relevantInfo = ""
    }

    /// A display title that falls back to provider/date when the user hasn't set one.
    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let provider = providerName?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            return "Visit with \(provider)"
        }
        if let date = appointmentDate {
            return "Appointment \(DateFormatter.mediumDate.string(from: date))"
        }
        return "Appointment Prep"
    }

    /// True once all three sections have generated content.
    var hasGeneratedContent: Bool {
        !timeline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !questions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !relevantInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Assembles the full shareable/printable report (mirrors the Python export format).
    var exportText: String {
        var lines: [String] = ["--- APPOINTMENT PREP REPORT ---", ""]

        if let date = appointmentDate {
            lines.append("APPOINTMENT DATE: \(DateFormatter.mediumDate.string(from: date))")
        }
        if let provider = providerName?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            lines.append("PROVIDER: \(provider)")
        }
        if appointmentDate != nil || (providerName?.isEmpty == false) {
            lines.append("")
        }

        func appendSection(_ label: String, _ content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            lines.append("\(label):")
            lines.append(trimmed)
            lines.append("")
        }

        appendSection("SYMPTOMS", symptoms)
        appendSection("ADDITIONAL NOTES", notes)
        appendSection("MEDICATIONS", medications)
        appendSection("TIMELINE", timeline)
        appendSection("QUESTIONS", questions)
        appendSection("RELEVANT INFO", relevantInfo)

        lines.append("---")
        lines.append("Generated by BisonHealth AI Appointment Prep")
        return lines.joined(separator: "\n")
    }
}
