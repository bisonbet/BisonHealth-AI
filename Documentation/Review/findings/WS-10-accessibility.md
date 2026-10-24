# WS-10 — Accessibility

- **Agent / model**: Claude (Sonnet 5.5), WS-10 subagent, read-only review
- **Date**: 2026-10-24
- **Commit reviewed**: f95cf804
- **Scope actually covered**: All 55 files under `Views/` plus `ContentView.swift`, `Utils/AccessibilityModifiers.swift`, `Utils/AccessibilityColors.swift`, `Utils/AccessibilityManager.swift`, `HealthAppApp.swift` (colour tokens). Ran the app on iPhone 17 Pro (UDID 21752144-…) from a fresh build and screenshotted: disclaimer (light/dark, default and AX5), Health records (light AX5, dark default), Lab Results entry incl. unit dropdown (light AX5), AI Chat empty state and conversation (dark default and AX5), Settings (dark AX5, light + Increase Contrast). 14 screenshots in `WS-10-screenshots/`. WCAG contrast ratios were computed from the literal RGB tokens in source.
- **Scope not covered**: **VoiceOver was never turned on** — every "VoiceOver reads X" statement below is reasoning from code and is marked PLAUSIBLE. Not exercised: hardware-keyboard Tab/Esc focus order and pointer hover (iPad, not my device); Split View/Slide Over/Stage Manager; Bold Text; Reduce Motion (code-only); document import and extracted-value review (needs a file picker and a processed document; BloodTestImportReviewView and DocumentDetailView were read, not driven); Vitals, Genetics, Imaging, Storage, Export, Privacy/Terms screens at AX5 (read only); chat reply reading and streaming — **on-device chat cannot run in the simulator** (`MLXOnDeviceLLM/` is compiled out), so no assistant bubble, streaming behaviour or announcement could be observed. Taps via the simulator tool were intermittently ignored/late, so flows were not driven end to end (personal-info save, saving a lab result were not completed).
- **Verdict**: Not accessibility-ready. The app is navigable, but its brand colour fails contrast wherever it is a fill or text colour (including the chat bubble and the first-launch Accept button), several primary screens break at the largest text sizes, and chat has no VoiceOver labelling at all. No P0/P1: nothing found makes the app unusable with assistive tech, and VoiceOver behaviour is unverified.
- **Counts**: P0=0 P1=0 P2=8 P3=7 (dropped: 2)

## Step 1 — coverage inventory (as specified)

`label` counts `accessibilityLabel` only. The project also has a `.voiceOverLabel(...)` wrapper (`Utils/AccessibilityModifiers.swift:65`, 18 call sites, all in `ContentView.swift` and `AppointmentPrepView.swift`), which the prescribed grep does not see; columns `vo` add those. `dynamicType`/`touchTarget`/`keyboardNavigable` helpers: see WS-10-10.

| File | label | vo | hint | id | value | Button( | Image( | flag |
|---|---|---|---|---|---|---|---|---|
| AWSBedrockSettingsView.swift | 1 | 0 | 1 | 0 | 0 | 5 | 1 |  |
| AppointmentPrepDetailView.swift | 2 | 0 | 0 | 2 | 0 | 5 | 2 |  |
| AppointmentPrepEditorView.swift | 3 | 0 | 0 | 6 | 0 | 3 | 1 |  |
| AppointmentPrepView.swift | 0 | 1 | 0 | 1 | 0 | 1 | 2 |  |
| BatchProcessingView.swift | 0 | 0 | 0 | 0 | 0 | 6 | 6 | interactive, no a11y modifiers |
| BloodTestEntryView.swift | 0 | 0 | 0 | 12 | 0 | 5 | 1 | interactive, no a11y modifiers |
| BloodTestImportReviewView.swift | 5 | 0 | 3 | 5 | 0 | 5 | 4 |  |
| BloodTestsSection.swift | 0 | 0 | 0 | 0 | 0 | 5 | 3 | interactive, no a11y modifiers |
| ChatDetailView.swift | 0 | 0 | 0 | 4 | 0 | 26 | 12 | interactive, no a11y modifiers |
| ChatEmptyStateView.swift | 0 | 0 | 0 | 0 | 0 | 1 | 3 | interactive, no a11y modifiers |
| ConnectionStatusBanner.swift | 0 | 0 | 0 | 0 | 0 | 1 | 1 | interactive, no a11y modifiers |
| ConversationListView.swift | 0 | 0 | 0 | 0 | 0 | 5 | 4 | interactive, no a11y modifiers |
| ConversationSidebarView.swift | 0 | 0 | 0 | 0 | 0 | 8 | 5 | interactive, no a11y modifiers |
| DataExportView.swift | 0 | 0 | 0 | 0 | 0 | 2 | 2 | interactive, no a11y modifiers |
| DatabaseUnavailableView.swift | 6 | 0 | 3 | 5 | 0 | 4 | 2 |  |
| DoctorSelectorView.swift | 0 | 0 | 0 | 0 | 0 | 3 | 1 | interactive, no a11y modifiers |
| DocumentCameraView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |
| DocumentDetailView.swift | 1 | 0 | 1 | 1 | 0 | 24 | 5 |  |
| DocumentFilterView.swift | 0 | 0 | 0 | 0 | 0 | 7 | 4 | interactive, no a11y modifiers |
| DocumentGridView.swift | 1 | 0 | 0 | 0 | 1 | 5 | 4 |  |
| DocumentListView.swift | 1 | 0 | 0 | 0 | 1 | 5 | 6 |  |
| DocumentTypeSelectorView.swift | 0 | 0 | 0 | 0 | 0 | 2 | 2 | interactive, no a11y modifiers |
| DocumentsEmptyStateView.swift | 0 | 0 | 0 | 0 | 0 | 4 | 3 | interactive, no a11y modifiers |
| DropdownComponents.swift | 0 | 0 | 0 | 0 | 0 | 8 | 7 | interactive, no a11y modifiers |
| FamilyHistoryEditorView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 0 | interactive, no a11y modifiers |
| FirstLaunchDisclaimerView.swift | 0 | 0 | 0 | 0 | 0 | 3 | 4 | interactive, no a11y modifiers |
| GeneticTestsSection.swift | 0 | 0 | 1 | 0 | 0 | 20 | 5 |  |
| HealthCheckupsSection.swift | 0 | 0 | 0 | 0 | 0 | 0 | 1 |  |
| HealthTabView.swift | 1 | 0 | 0 | 1 | 0 | 0 | 0 |  |
| ImagingReportsSection.swift | 0 | 0 | 0 | 0 | 0 | 0 | 1 |  |
| MedicalConditionEditorView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 0 | interactive, no a11y modifiers |
| MedicalDocumentDetailView.swift | 0 | 0 | 0 | 0 | 0 | 12 | 10 | interactive, no a11y modifiers |
| MedicationEditorView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 0 | interactive, no a11y modifiers |
| MedicationsListView.swift | 0 | 0 | 0 | 0 | 0 | 1 | 1 | interactive, no a11y modifiers |
| OfflineIndicatorView.swift | 0 | 0 | 0 | 0 | 0 | 1 | 4 | interactive, no a11y modifiers |
| OnDeviceLLMSettingsView.swift | 1 | 0 | 1 | 6 | 0 | 12 | 9 |  |
| OpenAICompatibleSettingsView.swift | 1 | 0 | 0 | 0 | 0 | 2 | 4 |  |
| PersonalInfoEditorView.swift | 0 | 0 | 0 | 7 | 0 | 5 | 0 | interactive, no a11y modifiers |
| PersonalInfoSection.swift | 0 | 0 | 0 | 0 | 0 | 1 | 7 | interactive, no a11y modifiers |
| PersonalMedicalHistoryView.swift | 0 | 0 | 0 | 0 | 0 | 3 | 1 | interactive, no a11y modifiers |
| PrivacyPolicyView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |
| RecentVitalsSection.swift | 0 | 0 | 0 | 0 | 0 | 7 | 5 | interactive, no a11y modifiers |
| SectionEditorView.swift | 0 | 0 | 0 | 0 | 0 | 3 | 0 | interactive, no a11y modifiers |
| SettingsView.swift | 2 | 0 | 2 | 2 | 0 | 23 | 12 |  |
| SplashScreenView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 2 |  |
| StorageUsageView.swift | 2 | 0 | 1 | 1 | 0 | 6 | 0 |  |
| SupplementEditorView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 0 | interactive, no a11y modifiers |
| SupplementSelectorView.swift | 0 | 0 | 0 | 0 | 0 | 9 | 3 | interactive, no a11y modifiers |
| SupplementsListView.swift | 0 | 0 | 0 | 0 | 0 | 1 | 1 | interactive, no a11y modifiers |
| TermsOfServiceView.swift | 0 | 0 | 0 | 0 | 0 | 1 | 0 | interactive, no a11y modifiers |
| TestTypePickerView.swift | 0 | 0 | 0 | 0 | 0 | 6 | 4 | interactive, no a11y modifiers |
| UnifiedContextSelectorView.swift | 3 | 0 | 3 | 2 | 1 | 6 | 10 |  |
| VitalEntryView.swift | 0 | 0 | 0 | 0 | 0 | 2 | 0 | interactive, no a11y modifiers |
| VitalsListView.swift | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |
| ContentView.swift | 10 | 17 | 1 | 8 | 0 | 18 | 17 |  |

**Reading the flags.** 32 of 56 files have interactive elements and no label/hint/value modifier. Most are controls with visible text (`Button("Save")`, `TextField("Full Name")`), which VoiceOver names automatically, so the count overstates the problem. The ones that matter are icon-only controls with no label — listed in WS-10-07 (Image(systemName:) as the only content of a Button, ~14 sites) — and the whole chat surface (`ChatDetailView`, `ConversationListView`, `ConversationSidebarView`, `ChatEmptyStateView`: 0 label/hint/value modifiers across 4 files, only 4 identifiers). Hint coverage is thin everywhere; hints on obvious controls are P3 and not itemised. `accessibilityHidden` appears 4 times, `accessibilityElement` 5 — decorative icons (`InfoRow`, empty states, splash) are mostly left exposed.

## Findings

### WS-10-01 — White text on the brand gold fails contrast everywhere it is used (chat bubble, Accept button, primary CTAs)
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/ChatDetailView.swift:606-609`; also `FirstLaunchDisclaimerView.swift:92`, `ChatEmptyStateView.swift:51`, `DatabaseUnavailableView.swift:152`, `MedicalDocumentDetailView.swift:545`, `ContentView.swift:1420`
- **Scenario**: Every message the user sends is white text on `BisonTheme.gold`. Gold is (0.78,0.55,0.16) in light mode and (0.93,0.70,0.28) in dark. Computed contrast of white on gold is **2.9:1 light and 1.9:1 dark** (WCAG AA needs 4.5:1 for body text). The first-launch "I Understand and Accept" button and "Start New Conversation" use the same pairing; the dark-mode screenshots show it washed out. The app already defines `BisonTheme.inkOnGold` (dark ink, 5.8:1 light / 9.0:1 dark) and uses it correctly in the Records/Documents switcher and sidebar — these sites missed it. Low-vision users cannot reliably read their own sent messages or the required legal notice button.
- **Evidence**:
  ```swift
  Text(message.content)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(messageBackground)      // BisonTheme.gold (or .opacity(0.7) while sending)
      .foregroundColor(.white)
  ```
  Screenshots `02-disclaimer-dark-default.png`, `03-disclaimer-light-default.png`, `10-chat-empty-dark-default.png` (button). The user bubble itself was not rendered (no send possible in the simulator); its colours are read from source, the ratio is arithmetic.
- **Fix**: Replace `.foregroundColor(.white)` with `BisonTheme.inkOnGold` at all six sites. While `.sending` the bubble is `gold.opacity(0.7)`; keep ink text so it stays above 4.5:1.
- **Blast radius**: Pure colour change at six call sites; no layout impact. Failed/retry bubbles (white on `Color.red.opacity(0.8)`, white on `Color.orange` for Retry, ~2.2:1) have the same defect and belong in the same pass.
- **Verification**: Recompute ratios for each fill; screenshot disclaimer, chat empty state and a sent bubble in light and dark; run Accessibility Inspector contrast audit.

### WS-10-02 — Brand gold used as text/tint on light backgrounds is 2.7:1 (all toolbar buttons, section "Edit"/"Add", "Add Test Result")
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `ContentView.swift:30` (`.tint(BisonTheme.gold)`), `Utils/AccessibilityColors.swift:25-28`, `Views/BloodTestEntryView.swift:116-120`
- **Scenario**: In light mode `gold` on `appBackground` is **2.7:1** and on the white card **2.9:1**. The app-wide tint is gold, so Cancel, Save, Edit, Add, Configure, "View Full Disclaimer", and tinted links all render in it. `Add Test Result` is gold text on a 10 %-gold fill (~2.5:1). The screenshots show `Cancel`, `Edit`, `Add` visibly faint. Dark mode is fine (9.9:1) and Increase Contrast does not help: `Color.adaptive` only has light/dark variants, and `colorSchemeContrast` is never read anywhere in the app.
- **Evidence**:
  ```swift
  static var gold: Color {
      Color.adaptive(
          light: Color(red: 0.78, green: 0.55, blue: 0.16),
          dark: Color(red: 0.93, green: 0.70, blue: 0.28)
      )
  }
  ```
  Screenshots `04-disclaimer-light-AX5.png`, `06-records-vitals-light-AX5.png` (Cancel/Save), `14-settings-light-increasecontrast.png`.
- **Fix**: Add a darker light-mode "gold text" token (e.g. the existing `hideBrown`, 6.9:1, or a gold darkened to ≥4.5:1) and use it for tint and text, keeping the bright gold for fills (with ink text, see 01). Optionally add a high-contrast variant keyed on `colorSchemeContrast`.
- **Blast radius**: Global tint change affects every screen; check the tab bar selected state and the segmented switcher (which uses gold as a fill).
- **Verification**: Contrast audit on light-mode Records, Lab entry, Settings; Increase Contrast on.

### WS-10-03 — Fixed-width icon columns collide with text at AX3–AX5 (Personal Information, Recent Vitals)
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/PersonalInfoSection.swift:195-198` (14 `.frame(width: 20|24|28|30|32)` sites in total); `ContentView.swift:1594-1597`
- **Scenario**: Set Larger Text to AX5. The Records screen's "Personal Information" header wraps mid-word ("Person-/al/Infor-/mation") next to the "Edit" button; in the card, the person and sex icons are drawn on top of the "Test User"/"Male" values, and the Recent Vitals icon overlaps its title. Information is still reachable by scrolling, but values are partly covered on the app's home screen.
- **Evidence**:
  ```swift
  HStack {
      Image(systemName: icon)
          .foregroundColor(BisonTheme.gold)
          .frame(width: 20)          // symbol scales with Dynamic Type, frame does not
      VStack(alignment: .leading, spacing: 2) { Text(label) ... Text(value) ... }
  ```
  Screenshot `05-health-records-light-AX5.png` (overlap visible); the Recent Vitals overlap was seen live but not saved.
- **Fix**: Use `@ScaledMetric` for the icon frame width or drop the fixed frame and use `Label`/`.imageScale`; give the Section header `.fixedSize(horizontal:false, vertical:true)` with the Edit button below the title at accessibility sizes (`dynamicTypeSize.isAccessibilitySize`).
- **Blast radius**: `InfoRow`/`InfoRowHeader` are reused in Lab detail, Documents, Medical history; fixing the shared struct fixes all.
- **Verification**: Re-screenshot Records at AX5 light/dark.

### WS-10-04 — Chat connection banner is unreadable at AX5 and fails contrast at every size
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/ConnectionStatusBanner.swift:9-37`
- **Scenario**: Opening a conversation in the simulator shows the orange "Connection Issue / Reconnecting to AI server…" banner (on a real device this is the only explanation when the model is unavailable). At AX5 the HStack gives the text column almost no width: the title renders as "Con-necti…" and the body as "Recon…", with a large Retry button taking the space. At default size the text is white and white@0.8 on system orange: ~2.2:1 and ~1.9:1. Also, "New Conver…" nav title is truncated at AX5.
- **Evidence**:
  ```swift
  Text(isOffline ? "AI assistant unavailable" : "Reconnecting to AI server...")
      .font(.caption2)
      .foregroundColor(.white.opacity(0.8))
  ...
  .background(isOffline ? Color.red : Color.orange)
  ```
  Screenshots `11-chat-conversation-dark-default.png`, `12-chat-conversation-dark-AX5.png`.
- **Fix**: At accessibility sizes stack vertically (`ViewThatFits` or `dynamicTypeSize.isAccessibilitySize` → VStack with Retry below); use ink/dark text on the banner or a darker banner fill; drop the 0.8 opacity. Add `.accessibilityElement(children: .combine)` so it reads as one status.
- **Blast radius**: Same white-on-orange/red pattern in `OfflineIndicatorView.swift:35` (global banner, also fixed `.system(size:)` 11-16pt fonts that do not scale at all — see WS-10-10) and `ChatDetailView.swift:590`.
- **Verification**: Chat at AX5 shows full title and message; contrast ≥4.5:1.

### WS-10-05 — First-launch disclaimer: pinned Accept bar consumes ~55 % of the screen at AX5
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/FirstLaunchDisclaimerView.swift:84-110`
- **Scenario**: A low-vision user with Larger Text at AX5 launches the app. The `safeAreaInset(edge: .bottom)` Accept button plus its two-line caption fill over half the iPhone 17 Pro screen; the legal notice is visible as a ~1.3-line window and must be scrolled in slivers, while the Accept button is always one tap away — i.e. the screen is biased toward accepting without reading. It is scrollable and not clipped, so this is a usability defect, not a block.
- **Evidence**:
  ```swift
  .safeAreaInset(edge: .bottom) {
      VStack(spacing: 16) {
          Button(action: { onAccept() }) { Text("I Understand and Accept") ...
          Text("You must accept this notice to use BisonHealth AI").font(.caption)
  ```
  Screenshot `04-disclaimer-light-AX5.png`.
- **Fix**: At accessibility sizes put the Accept button and caption inside the ScrollView (end of content) instead of a pinned inset.
- **Blast radius**: This single screen; nothing else uses it. Interacts with legal workstreams (acceptance semantics) — keep the "must accept" behaviour.
- **Verification**: Screenshot at AX5; confirm the notice is readable without scrolling past the button.

### WS-10-06 — Lab entry: Unit field fixed at 120 pt and the unit list clips at AX5
- **Severity**: P2 · **Confidence**: CONFIRMED (layout) · **Effort**: S
- **Location**: `Views/DropdownComponents.swift:157-162` (TextField `.frame(maxWidth: 120)`), `BloodTestEntryView.swift:309-349` (Value and Unit side by side)
- **Scenario**: Add a lab result at AX5. Value and Unit sit in a two-column HStack; the Unit field is capped at 120 pt, so its text truncates ("Unit" placeholder already clipped; "mg/dL" or "×10³/µL" will not fit). Opening the dropdown shows a ~200 pt-high list inside the narrow column where each row is huge: only "%" and "IU/L" are visible with the second row cut off, and nothing signals the list scrolls. The validation messages in the same row ("Test value is required") wrap into a five-line column.
- **Evidence**:
  ```swift
  TextField("Unit", text: $selectedUnit)
      .textFieldStyle(RoundedBorderTextFieldStyle())
      .frame(maxWidth: 120)
  ```
  Screenshots `07-labentry-valueunit-light-AX5.png`, `08-labentry-unitdropdown-light-AX5.png`.
- **Fix**: Stack Value and Unit vertically at accessibility sizes; replace the hand-rolled in-flow dropdown with `Menu`/`Picker` (system-managed sizing and VoiceOver semantics).
- **Blast radius**: `UnitDropdown`/`SearchableDropdownWithAddNew` also used for Laboratory/Physician. Flow 3 of the plan.
- **Verification**: AX5 screenshot; can select every unit in the list.

### WS-10-07 — Icon-only buttons rely on SF Symbol default names; dropdown chevrons have no state; several are small
- **Severity**: P2 · **Confidence**: PLAUSIBLE (unverified link: what VoiceOver actually speaks for these symbols — I could not run VoiceOver) · **Effort**: M
- **Location**: `Views/DropdownComponents.swift:30-37,181-188` (chevron.down toggles), `ChatDetailView.swift:207-213,719-725,756-763` (keyboard dismiss, iPad context, send), `ConversationSidebarView.swift:33-36`, `DocumentGridView.swift:62-68`, `RecentVitalsSection.swift:183-186`, `SupplementsListView.swift:43`, `MedicationsListView.swift:44`, `PersonalMedicalHistoryView.swift:50`, `SupplementSelectorView.swift:41`, `MedicalDocumentDetailView.swift:536`, `ContentView.swift:1412` (chip "xmark" remove buttons)
- **Scenario**: A VoiceOver user in the lab-entry sheet reaches the chevron next to "Laboratory Name". The button has no `accessibilityLabel`; iOS falls back to a generic symbol description (or the raw name), never "Show laboratory options", and the open/closed state is only a `rotationEffect`, so it is never announced. Same for chat Send (`arrow.up.circle.fill`), the document selection circle (`circle`/`checkmark.circle.fill`), and the chip "xmark" (which chip? "Close"). Also visibly small: the Send glyph measured ~22 pt on screen with no frame/padding (hit area not measured — second unverified link), well below 44 pt.
- **Evidence**:
  ```swift
  Button(action: { isShowingDropdown.toggle() }) {
      Image(systemName: "chevron.down")
          .foregroundColor(.secondary)
          .rotationEffect(.degrees(isShowingDropdown ? 180 : 0))
  }
  ```
- **Fix**: Add `.accessibilityLabel` per button (context-specific: "Show laboratory options", "Send message", "Remove <chip title>"), `.accessibilityValue(isShowingDropdown ? "Expanded" : "Collapsed")` on toggles, `.frame(minWidth: 44, minHeight: 44)`/`.touchTarget()` (helper exists, used in 8 places).
- **Blast radius**: ~14 sites; adding labels does not change layout except where frames are added.
- **Verification**: Accessibility Inspector audit (Image/Button description); manual VoiceOver pass over Lab entry and Chat.

### WS-10-08 — Lab values are read as unlinked fragments; abnormal status is colour + an unlabelled icon
- **Severity**: P2 · **Confidence**: PLAUSIBLE (unverified link: VoiceOver reading order/wording not heard) · **Effort**: S
- **Location**: `Views/BloodTestsSection.swift:253-290` (`BloodTestItemRow`); same pattern in the row list `BloodTestRowView` and `RecentVitalsSection.swift` rows
- **Scenario**: The core output of the app is a lab result. Each row is name, warning image, value, unit, reference range as separate accessibility elements: a VoiceOver user hears "Glucose … 110 … mg/dL … Reference: 70-100" in 4-5 swipes with the connection implicit, and an out-of-range result is signalled only by red text and an `exclamationmark.triangle.fill` with no label (the word "abnormal" never appears). Dropping any link in that chain (they are individual stops) loses the result's meaning.
- **Evidence**:
  ```swift
  if item.isAbnormal {
      Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.red)
          .font(.caption)
  }
  ...
  .foregroundColor(item.isAbnormal ? .red : .primary)
  ```
- **Fix**: `.accessibilityElement(children: .combine)` on the row plus `.accessibilityLabel("\(name), \(value) \(unit)\(isAbnormal ? ", abnormal" : ""), reference \(range)")`; add a text cue ("High/Abnormal") for sighted colour-blind users too.
- **Blast radius**: Lab list, lab detail, vitals rows, genetic/imaging rows if they use the same shape.
- **Verification**: Listen with VoiceOver; Accessibility Inspector shows a single element per row.

### WS-10-09 — AI Chat has no VoiceOver structure and no announcement of state changes (unverifiable in the simulator)
- **Severity**: P3 · **Confidence**: PLAUSIBLE (unverified link: the whole reply/streaming path is compiled out of the simulator build, so nothing here was observed) · **Effort**: M
- **Location**: `Views/ChatDetailView.swift:449-480` (`TypingIndicatorView`), `:600-720` (bubbles), `:422` (typing row); `AccessibilityNotification`/`UIAccessibility.post` has zero uses in the app
- **Scenario**: A VoiceOver user sends a message. The typing indicator is three unlabeled `Circle`s (the only readable text is "BisonHealth AI"), nothing is posted when a reply starts or finishes, and an assistant bubble is read as separate pieces (role icon, "BisonHealth AI", the markdown body, timestamp, "• N tokens", "• 1.2s"), so the user must hunt for the reply and cannot know it completed. The feared "re-announce on every token" bug is **not evidenced**: SwiftUI does not announce text changes without a live-region trait or a notification, and none is used; but if focus rests on the streaming `StructuredText`, partial text may be re-read — not testable here.
- **Evidence**:
  ```swift
  ForEach(0..<3) { index in
      Circle()
          .fill(Color.secondary)
          .frame(width: 8, height: 8)
          .scaleEffect(isAnimating ? 1.2 : 0.8)
          .animation(Animation.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: isAnimating)
  }
  ```
- **Fix**: Label the indicator ("BisonHealth AI is typing"), post `AccessibilityNotification.Announcement("Reply received")` once on completion, group each bubble with `.accessibilityElement(children: .combine)` and a role-prefixed label, hide metadata (tokens/time) from VoiceOver or read after the body.
- **Blast radius**: Chat only. Needs a device build with an installed model to verify.
- **Verification**: Device with MLX model; VoiceOver on; send a message; confirm one announcement on completion and no per-token speech.

### WS-10-10 — Dynamic Type helpers are inert; ~30 fixed-size fonts do not scale
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `Utils/AccessibilityManager.swift:40-42`, `Utils/AccessibilityModifiers.swift:6-22`; fixed sizes: `OfflineIndicatorView.swift:19-137` (11 sites, status text), `SplashScreenView.swift:53-80`, `ContentView.swift:240`, plus icons at 28-60 pt
- **Scenario**: The app *claims* Dynamic Type support (`.dynamicType(.body, isIPad:)` on Records/Documents/Prep) but `scaledFont(for:)` returns `self` and the modifier only sets `.body` plus `minimumScaleFactor(0.8)` (which makes text shrink instead of wrap when space runs out). The global offline banner ("No Internet Connection / Some features are unavailable") is `.system(size: 12-14)` and ignores the user's text size entirely; it is also white on orange (see 04). Most screens inherit system text styles and do scale (confirmed in screenshots), so the damage is concentrated in banners, splash and icons.
- **Evidence**:
  ```swift
  extension Font {
      /// Scales a font to support Dynamic Type
      func scaledFont(for textStyle: Font.TextStyle) -> Font {
          return self
      }
  }
  ```
- **Fix**: Replace `.system(size:)` on text with text styles (`.footnote`, `.subheadline`); use `@ScaledMetric` for icon sizes; delete the no-op `scaledFont`/`minimumScaleFactor` or make them real.
- **Blast radius**: Offline banner (global), splash, empty states.
- **Verification**: AX5 screenshots of offline banner (toggle airplane mode on the sim) and empty states.

### WS-10-11 — No heading traits anywhere; screen titles and section headers are plain text
- **Severity**: P3 · **Confidence**: CONFIRMED (grep) · **Effort**: S
- **Location**: all of `Views/`; the only trait support is the unused `.header` option in `AccessibilityModifiers.swift:85`
- **Scenario**: Custom headings such as "Important Notice", "Test Information", disclaimer cards and the Prep sections use `Text(...).font(.title2/.headline)` without `.accessibilityAddTraits(.isHeader)`, so the VoiceOver Headings rotor finds only List/Form section headers the system adds itself. Longer text screens (disclaimer, Privacy Policy, Terms) are read linearly.
- **Evidence**: `grep -rn 'isHeader\|\.header\]' Views ContentView.swift` returns nothing.
- **Fix**: Add `.accessibilityAddTraits(.isHeader)` to custom heading Texts (≈15 sites).
- **Blast radius**: None visual.
- **Verification**: Rotor → Headings on disclaimer, Privacy, Terms.

### WS-10-12 — Reduce Motion is never consulted; the typing indicator animates forever
- **Severity**: P3 · **Confidence**: CONFIRMED (grep; behaviour not observed) · **Effort**: S
- **Location**: `Views/ChatDetailView.swift:473` (`.repeatForever()`); 25 `withAnimation`/`.animation` uses, none gated; `accessibilityReduceMotion` has zero hits
- **Scenario**: With Reduce Motion on, the typing dots still pulse continuously during every response, and tab/section transitions animate normally. Impact is small (opacity fade splash, 0.15-0.2 s section animations) but the pulsing loop is the kind of persistent motion the setting exists for. Splash fades in over 0.5 s (acceptable).
- **Evidence**: see WS-10-09 snippet.
- **Fix**: Read `@Environment(\.accessibilityReduceMotion)`; show static dots/“…” when true.
- **Blast radius**: Chat typing indicator; optionally wrap `withAnimation` helpers.
- **Verification**: Enable Reduce Motion, observe indicator static.

### WS-10-13 — Low-contrast informational text (`tertiaryLabel`, 0.8-opacity white, validation shown on a pristine form)
- **Severity**: P3 · **Confidence**: CONFIRMED (visible in screenshots; ratio estimated for tertiaryLabel) · **Effort**: S
- **Location**: `Views/BloodTestEntryView.swift:171-175` and `BloodTestsSection.swift:158`; `BloodTestEntryView.swift:45-48,112-115` (validation)
- **Scenario**: Hint copy such as "Add individual test results to create a complete lab results record" and "Tap Add to record your lab results" is `Color(.tertiaryLabel)` (~2:1 on white). Separately, the lab form shows red "At least one test result is required" and a dimmed Save the instant it opens, and per-field "Test name is required" under a just-added empty row; none is announced, and a VoiceOver user hears only a dimmed Save with no reason attached.
- **Evidence**: `.foregroundColor(Color(.tertiaryLabel))` on the explanatory text; screenshots `07-…`, `09-health-dark-default.png`.
- **Fix**: Use `.secondary` for informative copy; show validation only after first edit or attempted save, and post an announcement or attach the error to the Save button via `accessibilityHint`.
- **Blast radius**: All empty states using tertiaryLabel.
- **Verification**: Visual contrast; VoiceOver on Save.

### WS-10-14 — Lab-entry repeated fields have no per-row context
- **Severity**: P3 · **Confidence**: PLAUSIBLE (unverified: VoiceOver wording) · **Effort**: S
- **Location**: `Views/BloodTestEntryView.swift:292-350` (`BloodTestItemEditor`)
- **Scenario**: A user adding five tests gets five identical sets of "Value", "Unit", "Reference Range", "Abnormal Result" fields. The caption `Text("Value")` above is a separate element and the field is named only by its placeholder, so nothing says which test a field belongs to. Also the custom-name field is `.disabled` while a standard test is chosen yet carries `.onTapGesture` to reset it — an affordance a VoiceOver user (dimmed element) is unlikely to discover.
- **Evidence**: `TextField("Value", text: …)` / `TextField("Reference Range", …)` inside `ForEach(results)` with no `.accessibilityLabel`.
- **Fix**: `.accessibilityElement(children: .contain)` per row with `.accessibilityLabel(item.name.isEmpty ? "Result \(n)" : item.name)`, or label each field "Value for <test>".
- **Blast radius**: Lab entry only (same editor used for edit).
- **Verification**: VoiceOver swipe through two rows.

### WS-10-15 — Step 4: `AccessibilityUITests` coverage — what it would and would not prove (and test-id gaps)
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: M (test-reliability finding, not an accessibility finding)
- **Location**: `HealthAppUITests/AccessibilityUITests.swift:14-240`; membership already tracked as WS-01-08 / tracker item 25 (not re-reported)
- **Scenario**: Even if added to the target it would prove almost nothing. It targets tabs "Health Data" and "Documents" and ids `tab.healthData`/`tab.documents`, which no longer exist (tabs are Health, Prep, AI Chat, Settings; `ContentView.swift:38-70`), so every body hides behind `if tab.exists { … }` and silently passes. Its assertions are vacuous: `XCTAssertNotNil(x.label)` (non-optional String), `isHittable` for the "colour contrast" test, an `isAccessibilityElement || isHittable` check for "Dynamic Type" with no size change, 44 pt size checks on the first 5 buttons of a tab it cannot reach. It never launches with a larger content size or VoiceOver, so the app should get **no credit** for these tests. The tab identifiers are applied to the tab *content* (`.tag(...).accessibilityIdentifier("tab.health")`), not the tab button, which is the likely reason selectors on `tabBars.buttons` would fail. Missing identifiers on the beta flows: disclaimer Accept button, Add Lab Results/Add (Records), Cancel/Save in Personal Info, Documents import controls, Settings controls; present: `bloodTest.*`, `personalInfo.*`, `chat.messageInput`, `chat.sendButton`, `typingIndicator`.
- **Evidence**:
  ```swift
  let healthDataTab = app.tabBars.buttons["Health Data"]
  if healthDataTab.exists { … XCTAssertNotNil(healthDataTab.label, …) }
  ```
- **Fix**: When the orphaned files are rejoined, rewrite against current tab names and `XCTAssertTrue(exists)` first; add Dynamic Type (`launchArguments: ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]`) and `performAccessibilityAudit()` (iOS 17+) as the actual accessibility gate; add identifiers on the disclaimer Accept button and the Records "Add" controls.
- **Blast radius**: Test target only.
- **Verification**: `RegressionSmokeUITests` (the only live UI test) stays green; new audit test runs in CI.

## Dropped (2)
- Menu items such as "Add Imaging Report"/"Add Medical Visit" are disabled placeholders whose `.voiceOverLabel` text differs from the visible title (Voice Control "label in name" mismatch) — `ContentView.swift:326-346`. P3, product decision more than accessibility.
- `.keyboardNavigable()` = `.focusable()` applied to whole `List`s (`ContentView.swift:475,957`) may add an extra keyboard-focus stop on iPad; could not be tested (no hardware keyboard session). P3, PLAUSIBLE.

## Per-flow VoiceOver walkthrough (VoiceOver itself not run — reasoning plus screenshots)
1. **First launch → accept**: Title, three cards and buttons are standard Text/Button and read in order; Accept button is named by its text. No heading traits (WS-10-11). Contrast of the button (WS-10-01) and AX5 layout (WS-10-05) are the sighted-blockers. First sighted-only assumption: none that blocks progress.
2. **Personal info → save**: Not driven. Static: fields are `TextField("Full Name")`, Pickers with titles; ids present; "Save" is a text button. Gold toolbar text 2.7:1 (WS-10-02). No blocker identified.
3. **Add blood test incl. unit picker**: First blocker is the dropdown chevron — no label, no expanded state (WS-10-07); unit list is a custom in-flow list (WS-10-06); fields lack per-row context (WS-10-14); validation silently disables Save (WS-10-13).
4. **Import document, read extracted values**: Not run. `BloodTestImportReviewView` has 5 labels/3 hints and a combined element at `:224` (best-covered screen). Lab value rows are unlinked fragments (WS-10-08).
5. **Chat send/reply**: Input and Send have identifiers only; Send has no label (WS-10-07); typing indicator unlabeled, no completion announcement (WS-10-09). Streaming spam not evidenced; reply path unverifiable here.
6. **Tab bar and settings**: Tab items have explicit labels and the system `TabView` (good); iPad sidebar buttons have `.isSelected`; the Records/Documents switcher has labels + `.isSelected` (good). Settings at AX5 and with Increase Contrast render legibly (screenshots 13, 14).

## Configurations tried (screenshots in `WS-10-screenshots/`)
Light/dark, default and AX5 (`accessibility-extra-extra-extra-large`), Increase Contrast on (Settings). Bold Text and Reduce Motion: not tried (no simulator switch reachable with the tooling used; Reduce Motion assessed from source only).

## Structural risks (max 5 bullets)
- Accessibility is a copy of helpers that do not do their job (`scaledFont` no-op, `keyboardNavigable`, a parallel `AccessibilityTraits` enum) rather than the system defaults; the only real gate is none — add `performAccessibilityAudit()` to the live UI test target.
- The brand palette has one colour (`gold`) doing four jobs (fill, text, tint, border); contrast cannot be fixed per call site, only by splitting tokens.
- Custom controls (segmented switcher, dropdowns, chips, typing indicator) replace system ones, each re-creating labelling/state by hand; every one found had a gap.
- The chat surface, the product's headline feature, has the least accessibility coverage and cannot be exercised in the simulator, so regressions there are invisible to CI.
- Tertiary/decorative text styles (`tertiaryLabel`, `.opacity(0.8)`) are used for information, not decoration.

## Machine-readable summary
```json
[
  {"id":"WS-10-01","title":"White text on brand gold fails contrast (chat bubble, Accept button, CTAs)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ChatDetailView.swift:609","HealthApp/HealthApp/Views/FirstLaunchDisclaimerView.swift:92","HealthApp/HealthApp/Views/ChatEmptyStateView.swift:51"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-02","title":"Gold text/tint on light backgrounds is 2.7:1","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Utils/AccessibilityColors.swift:25","HealthApp/HealthApp/ContentView.swift:30"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-03","title":"Fixed-width icon columns overlap text at AX5","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/PersonalInfoSection.swift:198","HealthApp/HealthApp/ContentView.swift:1597"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-04","title":"Connection banner unreadable at AX5 and low contrast","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ConnectionStatusBanner.swift:9"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-05","title":"Disclaimer Accept bar takes ~55% of screen at AX5","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/FirstLaunchDisclaimerView.swift:84"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-06","title":"Lab entry unit field fixed 120pt; unit list clips at AX5","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DropdownComponents.swift:162","HealthApp/HealthApp/Views/BloodTestEntryView.swift:309"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-07","title":"Icon-only buttons unlabeled, dropdown chevrons stateless, small targets","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/DropdownComponents.swift:30","HealthApp/HealthApp/Views/ChatDetailView.swift:756"],"effort":"M","area":"accessibility"},
  {"id":"WS-10-08","title":"Lab value rows unlinked; abnormal flag colour+icon only","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/BloodTestsSection.swift:262"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-09","title":"Chat: unlabeled typing indicator, ungrouped bubbles, no announcements","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/ChatDetailView.swift:463"],"effort":"M","area":"accessibility"},
  {"id":"WS-10-10","title":"Dynamic Type helpers inert; fixed-size fonts do not scale","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Utils/AccessibilityManager.swift:40","HealthApp/HealthApp/Views/OfflineIndicatorView.swift:19"],"effort":"M","area":"accessibility"},
  {"id":"WS-10-11","title":"No heading traits in any view","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-12","title":"Reduce Motion never consulted; infinite typing animation","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ChatDetailView.swift:473"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-13","title":"tertiaryLabel/0.8-opacity informational text; eager validation unannounced","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/BloodTestEntryView.swift:171","HealthApp/HealthApp/Views/BloodTestsSection.swift:158"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-14","title":"Lab entry repeated fields lack per-row context","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/BloodTestEntryView.swift:292"],"effort":"S","area":"accessibility"},
  {"id":"WS-10-15","title":"AccessibilityUITests vacuous even if compiled; test-id gaps (test reliability)","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthAppUITests/AccessibilityUITests.swift:14"],"effort":"M","area":"accessibility"}
]
```
