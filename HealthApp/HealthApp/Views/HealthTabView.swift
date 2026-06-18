import SwiftUI

// MARK: - Health Tab (merged Records + Documents)
/// Combines the health record and document management into one tab. A single
/// navigation bar owns a segmented scope switch in its title (principal)
/// position; each child renders content-only so there is exactly one nav bar.
struct HealthTabView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case records = "Records"
        case documents = "Documents"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .records

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        segmentSwitcher
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .records:
            HealthDataView(embedInNavigation: false)
        case .documents:
            DocumentsView(embedInNavigation: false)
        }
    }

    // MARK: - Themed Segmented Control
    /// Custom segmented control — the native `.segmented` picker renders the
    /// selected segment's label unreadably against the dark theme.
    private var segmentSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(Segment.allCases) { item in
                let isSelected = segment == item
                Button {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(.easeInOut(duration: 0.15)) { segment = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? BisonTheme.inkOnGold : BisonTheme.secondaryText)
                        .lineLimit(1)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? BisonTheme.gold : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BisonTheme.panelBackground)
        )
        .accessibilityIdentifier("health.segment")
        .accessibilityElement(children: .contain)
    }
}
