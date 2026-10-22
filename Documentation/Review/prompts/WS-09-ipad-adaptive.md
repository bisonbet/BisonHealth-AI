# WS-09 — iPad & adaptive layout

**Phase 2 · model tier: mid · output: `Documentation/Review/findings/WS-09-ipad-adaptive.md`**

`TARGETED_DEVICE_FAMILY = "1,2"` means Apple's reviewer will open this on an iPad, and
an iPad bug is a rejection risk as well as a beta complaint. The project also allows all
four orientations on iPad but portrait-only on iPhone.

## What to examine

**1. Static audit.** For all 54 files in `HealthApp/HealthApp/Views/` plus `ContentView`:

```bash
grep -rn 'horizontalSizeClass\|verticalSizeClass\|NavigationSplitView\|UIDevice.current.userInterfaceIdiom' HealthApp/HealthApp --include='*.swift'
grep -rn 'NavigationView' HealthApp/HealthApp --include='*.swift'   # must stay empty
grep -rn 'frame(width:\|frame(height:\|\.frame(minWidth' HealthApp/HealthApp --include='*.swift'
grep -rn 'UIScreen.main' HealthApp/HealthApp --include='*.swift'
```

Flag: hardcoded widths/heights that assume a phone; `UIScreen.main.bounds` (wrong under
Split View and Stage Manager); any view that branches on idiom instead of size class.

**2. Which views adapt and which don't.** Build a table of every top-level screen:
adaptive (size-class aware) / phone-only layout / untested. A screen that renders a
320-pt-wide column centred in a 1024-pt iPad window is a P2 finding, not a nitpick —
Apple's reviewers do call this out.

**3. Run it.** Launch on `iPad Pro 11-inch (M5)` and walk the primary flows:
first launch → add personal info → add a blood test → import a document → chat → settings
→ appointment prep → export. Screenshot each. Then repeat with:
- landscape and portrait,
- Split View at 1/2 and 1/3 width,
- Stage Manager with a resized window (if available on the runtime),
- an external keyboard attached (`UIApplicationSupportsIndirectInputEvents` is on — check
  focus order, Tab traversal, Escape to dismiss sheets, and ⌘-key shortcuts if any),
- a trackpad/pointer (hover states).

Use the iOS Simulator tools available to you for launching, screenshotting, and tapping.
Attach the live panel first so the human can watch.

**4. Multi-window.** If the app supports more than one window on iPad, open two and check
shared singletons don't fight (e.g. both windows editing the same record, or one window's
stream updating the other's UI). If multi-window is not supported, confirm that is
deliberate and declared.

**5. Rotation.** Rotate on every screen with a sheet or keyboard open. Look for layout
jumps, lost keyboard focus, truncated content, and sheets that resize into an unusable
shape.

**6. Keyboard avoidance.** Text entry on iPad with a floating keyboard and with a hardware
keyboard — is the field visible, does the scroll view inset correctly?

**7. Pointer and drag-and-drop.** Does importing a document by dragging a PDF onto the app
work? Not required, but if the UI implies it, it must.

**8. iPhone regression check.** Everything you flag as an iPad fix must not break iPhone.
Re-run the same primary flow on `iPhone 17 Pro` and confirm parity.

## Output

Plan §1.6 contract, plus the **screen adaptivity table** (screen → iPad layout verdict →
evidence: screenshot path or file:line). Save screenshots under
`Documentation/Review/findings/WS-09-screenshots/` with descriptive names.

If you could not run the simulator, say so plainly in `Scope not covered` and mark the
workstream as static-only — do not describe screens you did not see.
