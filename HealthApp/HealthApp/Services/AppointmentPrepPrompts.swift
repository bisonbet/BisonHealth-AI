import Foundation

// MARK: - Appointment Prep Prompts
/// Prompt templates for the appointment-prep workflow.
///
/// Ported verbatim from the Python `medical-appt-prep` tool (`src/prompts.py`)
/// so the proven instructions and section formats are preserved. The three
/// section prompts are run as separate LLM calls; the user's broader health
/// record is supplied separately as `context` to the provider.
enum AppointmentPrepPrompts {

    /// System prompt sent with every appointment-prep generation call.
    static let systemPrompt = """
    You are a knowledgeable medical assistant helping a patient prepare for a \
    doctor's appointment. Provide clear, organized, and accurate information. \
    Always remind the user to consult their healthcare provider for medical \
    decisions. Use plain language.
    """

    /// Disclaimer suffix enforced on the Relevant Info section.
    static let disclaimerSuffix = "This is informational only and not a substitute for professional medical advice."

    // MARK: - Context Block

    private static func formatSection(_ label: String, _ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "**\(label):**\n\(trimmed)"
    }

    /// Builds the "Patient Information" block from the appointment-specific inputs.
    static func contextBlock(symptoms: String, notes: String, medications: String) -> String {
        var parts: [String] = []
        if let s = formatSection("Symptoms", symptoms) { parts.append(s) }
        if let n = formatSection("Additional Notes", notes) { parts.append(n) }
        if let m = formatSection("Current Medications", medications) { parts.append(m) }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Section Prompts

    static func timelinePrompt(symptoms: String, notes: String, medications: String) -> String {
        let context = contextBlock(symptoms: symptoms, notes: notes, medications: medications)
        return """
        You are helping a patient organize their symptom history before a doctor's appointment.

        Write only the patient-facing timeline. Do not write thoughts, planning,
        analysis, or comments about this prompt. Do not diagnose.

        Create 3-5 concise bullets that:
        - Organize symptoms by timing when possible.
        - Note patterns, triggers, aggravating factors, and relieving factors.
        - Highlight what seems new, ongoing, or changing.
        - Do not invent timing. If timing is not provided, say "timing not specified."

        --- Patient Information ---
        \(context)
        ---

        Start directly with the bullets. Do not include a heading, introduction, notes
        section, or subsection.
        """
    }

    static func questionsPrompt(symptoms: String, notes: String, medications: String) -> String {
        let context = contextBlock(symptoms: symptoms, notes: notes, medications: medications)
        return """
        You are helping a patient prepare thoughtful questions for their upcoming doctor's appointment.

        Write only patient-facing questions. Do not write thoughts, planning, analysis,
        answers, or comments about this prompt. Do not diagnose.

        Create 5 concise questions the patient can ask their doctor. Include questions
        about possible causes, tests, medication concerns, urgency, and follow-up. Keep
        each question under 20 words.

        --- Patient Information ---
        \(context)
        ---

        Start directly with question 1. Do not include a heading or introduction.
        """
    }

    static func relevantInfoPrompt(symptoms: String, notes: String, medications: String) -> String {
        let context = contextBlock(symptoms: symptoms, notes: notes, medications: medications)
        return """
        You are helping a patient prepare for a doctor's appointment.

        Write only patient-facing background information. Do not write thoughts,
        planning, analysis, or comments about this prompt. Do not diagnose or claim
        certainty.

        Create exactly 4 concise bullets that may help the patient talk with their
        doctor. Keep each bullet under 22 words. Mention general red flags and
        medication-related considerations only when relevant. Make the last bullet a
        short reminder that this is informational only and not a substitute for
        professional medical advice.

        --- Patient Information ---
        \(context)
        ---

        Start directly with the bullets. Do not include a heading, introduction,
        subsection, or "important considerations" section.
        """
    }
}
