import SwiftUI

// MARK: - Health Tab (merged Records + Documents)
/// Combines the health record and document management into one tab. Records sits in a
/// stack owned here; Documents owns a split view so the list and the open document can sit
/// side by side on iPad and the open iPhone Duo.
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

    /// Records is one column in a stack. Documents brings its own split view — the list
    /// beside the open document at regular width, a stack with the document pushed on
    /// compact width — so it gets the switch pinned to its list column instead.
    @ViewBuilder
    var body: some View {
        switch segment {
        case .records:
            NavigationStack {
                HealthDataView()
                    .pinnedSegmentSwitcher(segmentSwitcher)
            }
        case .documents:
            DocumentsView(listHeader: segmentSwitcher)
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

// MARK: - Pinned Segment Switcher
/// Pins the Records/Documents switch above a column's content.
///
/// The switch is centred, which on a partly folded iPhone Duo is exactly where the fold
/// runs; Apple asks for controls to be kept clear of it, so while a fold divides the column
/// it moves to the leading half. In the Documents split view the fold usually falls on the
/// column boundary instead, so the list column is not divided and the switch stays centred.
private struct PinnedSegmentSwitcher<Switcher: View>: ViewModifier {
    let switcher: Switcher
    @State private var isDividedByFold = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                switcher
                    .frame(maxWidth: .infinity, alignment: isDividedByFold ? .leading : .center)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(BisonTheme.appBackground)
            }
            // Each segment titles itself ("Health Data", "Documents").
            .toolbarTitleDisplayMode(.inline)
            .onGeometryChange(for: Bool.self) { proxy in
                PlatformCapabilities.isDividedByFold(proxy)
            } action: { divided in
                isDividedByFold = divided
            }
    }
}

extension View {
    func pinnedSegmentSwitcher<Switcher: View>(_ switcher: Switcher) -> some View {
        modifier(PinnedSegmentSwitcher(switcher: switcher))
    }
}
