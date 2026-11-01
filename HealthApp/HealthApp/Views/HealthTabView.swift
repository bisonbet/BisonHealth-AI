import SwiftUI

// MARK: - Health Tab (merged Records + Documents)
/// Combines the health record and document management into one tab. One navigation bar,
/// owned here; each child renders content only.
///
/// The Records/Documents switch is pinned above the content, not in the bar's principal
/// slot. On iPhone Duo bars move to the side of the display, and a custom view in a toolbar
/// is never presented there, so the tab's main control ended up stranded in a leftover
/// horizontal strip. Above the content it stays put in every pose, next to what it changes.
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    segmentSwitcher
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(BisonTheme.appBackground)
                }
                // Each segment titles itself ("Health Data", "Documents").
                .toolbarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .records:
            HealthDataView()
        case .documents:
            DocumentsView()
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
