# WS-10 — Accessibility

**Phase 2 · model tier: cheap (checklist-driven) · output:
`Documentation/Review/findings/WS-10-accessibility.md`**

`CLAUDE.md` requires every UI component to have accessibility support. The codebase has
~60 `accessibilityIdentifier` and ~41 `accessibilityLabel` calls across 54 view files, so
coverage is partial. A health app with unreadable lab values is a real exclusion, and
Apple's reviewers do test VoiceOver.

This workstream is mechanical. Follow it literally; do not improvise.

## Step 1 — coverage inventory

For every file in `HealthApp/HealthApp/Views/` plus `ContentView.swift`, count:

```bash
for f in HealthApp/HealthApp/Views/*.swift HealthApp/HealthApp/ContentView.swift; do
  printf "%s label=%s hint=%s id=%s value=%s button=%s image=%s\n" "$(basename "$f")" \
    "$(grep -c 'accessibilityLabel' "$f")" "$(grep -c 'accessibilityHint' "$f")" \
    "$(grep -c 'accessibilityIdentifier' "$f")" "$(grep -c 'accessibilityValue' "$f")" \
    "$(grep -c 'Button(' "$f")" "$(grep -c 'Image(' "$f")"
done
```

Produce the table. Flag any view with interactive elements (`Button`, `Toggle`,
`TextField`, `Picker`, tappable `onTapGesture`) and zero accessibility modifiers. Flag
every `Image(systemName:)` used as the only content of a control with no label — those
read as "button" with no meaning.

## Step 2 — targeted checks

```bash
grep -rn 'accessibilityElement\|accessibilityHidden\|accessibilityAddTraits\|accessibilitySortPriority' HealthApp/HealthApp --include='*.swift'
grep -rn 'Text(.*\\(.*)\)' HealthApp/HealthApp/Views --include='*.swift' | head -40   # interpolated values needing accessibilityValue
grep -rn 'font(.system(size:' HealthApp/HealthApp --include='*.swift'                 # fixed sizes defeat Dynamic Type
grep -rn 'lineLimit(1)\|truncationMode' HealthApp/HealthApp --include='*.swift'        # truncation at large text sizes
grep -rn 'Color(red:\|Color(.sRGB\|foregroundColor(.gray' HealthApp/HealthApp --include='*.swift'  # contrast risks
```

- Fixed `.system(size:)` fonts: each is a Dynamic Type failure. List them.
- `lineLimit(1)` on anything carrying a value or label: check it at AX5 text size.
- Hardcoded colours: check contrast against both light and dark backgrounds; flag any
  below 4.5:1 for body text.

## Step 3 — run VoiceOver flows in the simulator

Launch on `iPhone 17 Pro`. For each flow below, walk it with VoiceOver reasoning about
what each element announces (or, if you can enable VoiceOver, with it on), and record the
first point where a sighted-only assumption blocks progress:

1. First launch → accept disclaimer.
2. Enter personal info and save.
3. Add a blood test result, including the unit picker.
4. Import a document and read its extracted values.
5. Send a chat message and read the streamed reply. (Streaming text that re-announces on
   every token is a specific, common, and severe bug — check for it.)
6. Navigate the tab bar and settings.

Then test with:
- Dynamic Type at AX3 and AX5 (`Settings > Accessibility > Display & Text Size > Larger Text`),
- Bold Text on,
- Reduce Motion on (check any splash/transition animation respects it),
- Dark mode, and Increase Contrast on.

Screenshot each configuration of the main screens into
`Documentation/Review/findings/WS-10-screenshots/`.

## Step 4 — UI test identifiers

`HealthAppUITests/AccessibilityUITests.swift` (~240 LOC) exists. Determine what it
actually asserts, and whether the identifiers the UI tests rely on are present on the
elements the beta flows use. Missing identifiers are a test-reliability finding, not an
accessibility finding — mark them as such.

## Severity guidance

- A control VoiceOver cannot identify, or a value a VoiceOver user cannot read → P2.
- Text clipped or overlapping at AX5 on a primary screen → P2.
- Streaming text that spams announcements → P2.
- Missing hints on obvious controls, or contrast marginally below target → P3.
- Nothing here is a P0 unless the app is unusable with VoiceOver on.

## Output

Plan §1.6 contract, plus the Step 1 coverage table and a per-flow VoiceOver walkthrough
result. Be explicit in `Scope not covered` about which checks were static-only.
