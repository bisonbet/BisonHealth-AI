import UIKit
import UniformTypeIdentifiers

// MARK: - Private Pasteboard

/// Copies text that may hold health information.
///
/// `UIPasteboard.general.string = …` publishes it to Universal Clipboard, where every nearby
/// Mac and iPad on the Apple ID can paste it, and leaves it there indefinitely for any app
/// that reads the pasteboard. This keeps the copy on this device and lets it lapse (WS-07-11).
enum PrivatePasteboard {
    /// Long enough to switch apps and paste; short enough that a forgotten copy does not sit
    /// on the pasteboard for the rest of the day.
    static let lifetime: TimeInterval = 10 * 60

    static func copy(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(lifetime)
            ]
        )
    }
}
