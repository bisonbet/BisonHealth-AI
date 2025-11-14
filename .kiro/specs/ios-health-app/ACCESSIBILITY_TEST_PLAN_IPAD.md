# Accessibility Test Plan - iPad

## Overview
This test plan verifies accessibility features on iPad devices, including VoiceOver support, Dynamic Type with iPad-optimized scaling, keyboard navigation, larger touch targets, and iPad-specific layout optimizations.

## Prerequisites
- iPad device or iPad simulator (iOS 17+)
- External keyboard (optional, for keyboard navigation tests)
- VoiceOver enabled
- Test with various Dynamic Type sizes
- Test in both Light and Dark modes
- Test in both portrait and landscape orientations

---

## Test 1: VoiceOver Support

### 1.1 Tab Bar Navigation
**Steps:**
1. Launch the app
2. Enable VoiceOver (Settings → Accessibility → VoiceOver → On, or triple-click home button if configured)
3. Swipe right to navigate through tab bar items
4. Listen to VoiceOver announcements

**Expected Results:**
- Each tab announces: "Health Data, button", "Documents, button", "AI Chat, button", "Settings, button"
- Each tab has a descriptive label
- Tabs are easily navigable with swipe gestures
- Tab bar is optimized for iPad's larger screen

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.2 Health Data View - iPad Layout
**Steps:**
1. Navigate to "Health Data" tab using VoiceOver
2. Double-tap to activate
3. Swipe right to navigate through the view
4. Test the "Add Health Data" button
5. Rotate to landscape and repeat

**Expected Results:**
- Navigation title "Health Data" is announced
- "Add Health Data" button announces: "Add Health Data, button, Menu to add new health data entries"
- Layout adapts to iPad's larger screen
- Content is well-organized in landscape
- All elements remain accessible in both orientations

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.3 Documents View - Grid and List Modes
**Steps:**
1. Navigate to "Documents" tab
2. Test view mode toggle (List/Grid) - iPad only feature
3. Navigate through documents in both modes
4. Test search and filter functionality

**Expected Results:**
- View mode toggle announces: "View Mode, button, Switch between list and grid view"
- List view items are accessible
- Grid view items are accessible
- Search field is properly labeled
- Filter button state is announced
- All document information is readable

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.4 Chat View - Split View (iPad)
**Steps:**
1. Navigate to "AI Chat" tab
2. Verify split view layout (sidebar + detail)
3. Navigate sidebar with VoiceOver
4. Test conversation selection
5. Test message input

**Expected Results:**
- Sidebar is accessible
- Conversation list items are clearly labeled
- Detail view is accessible
- Message input has proper label
- Split view navigation is logical

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.5 Settings View - iPad Layout
**Steps:**
1. Navigate to "Settings" tab
2. Navigate through all settings sections
3. Test theme toggle
4. Test haptic feedback toggle
5. Verify layout uses iPad's larger screen effectively

**Expected Results:**
- All settings are accessible
- Layout is optimized for iPad
- Settings are well-organized
- Toggles announce their current state

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 2: Dynamic Type Support - iPad Optimized

### 2.1 Text Scaling - Smallest Size
**Steps:**
1. Go to Settings → Display & Brightness → Text Size
2. Set to smallest size
3. Return to app
4. Navigate through all main views
5. Test in both portrait and landscape

**Expected Results:**
- All text remains readable
- Text scales appropriately
- iPad layout handles scaling well
- No text is cut off or overlapping
- Layout adapts gracefully

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 2.2 Text Scaling - Largest Size
**Steps:**
1. Go to Settings → Display & Brightness → Text Size
2. Set to largest size
3. Return to app
4. Navigate through all main views
5. Test in both orientations

**Expected Results:**
- All text scales to largest size
- Text remains readable
- Layout adapts without breaking
- iPad's larger screen accommodates large text well
- No horizontal scrolling needed for normal content

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 2.3 Accessibility Text Sizes - iPad
**Steps:**
1. Go to Settings → Accessibility → Display & Text Size → Larger Text
2. Enable "Larger Accessibility Sizes"
3. Set to maximum size
4. Test app navigation in both orientations

**Expected Results:**
- Text scales to accessibility sizes
- App remains functional
- iPad's screen space is used effectively
- Buttons and interactive elements remain accessible
- Layout adapts gracefully to large text

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 3: Color Contrast and Accessibility Colors

### 3.1 Light Mode Contrast - iPad
**Steps:**
1. Set device to Light Mode
2. Navigate through all views
3. Check text readability on all backgrounds
4. Verify button text is readable
5. Test in both orientations

**Expected Results:**
- Text has sufficient contrast (WCAG AA: 4.5:1 for normal text)
- Button text is clearly visible
- Status colors (success, error, warning) are distinguishable
- No text blends into background
- Colors work well on iPad's larger display

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 3.2 Dark Mode Contrast - iPad
**Steps:**
1. Set device to Dark Mode
2. Navigate through all views
3. Check text readability on all backgrounds
4. Verify button text is readable
5. Test in both orientations

**Expected Results:**
- Text has sufficient contrast in dark mode
- Button text is clearly visible
- Status colors are distinguishable
- No text blends into dark backgrounds
- Dark mode looks good on iPad's display

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 3.3 Automatic Theme Switching - iPad
**Steps:**
1. Set theme to "System" in app settings
2. Change device theme between Light and Dark
3. Verify app theme updates automatically
4. Check that colors adapt correctly
5. Test in both orientations

**Expected Results:**
- App theme switches automatically
- Colors adapt to new theme
- No visual glitches during transition
- All text remains readable
- Works correctly in both orientations

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 4: Haptic Feedback - iPad

### 4.1 Haptic Feedback - Enabled (iPad uses lighter feedback)
**Steps:**
1. Ensure haptic feedback is enabled in Settings
2. Tap various buttons throughout the app
3. Note the feedback intensity (should be lighter than iPhone)

**Expected Results:**
- Button taps provide light impact haptic feedback (iPad-optimized)
- Success actions provide success haptic
- Error actions provide error haptic
- Selection changes provide selection haptic
- Feedback is appropriate for iPad (lighter than iPhone)

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 4.2 Haptic Feedback - Disabled
**Steps:**
1. Disable haptic feedback in app Settings
2. Perform various actions

**Expected Results:**
- No haptic feedback is provided
- App functions normally
- Visual feedback still works

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 5: Touch Target Sizes - iPad (48pt minimum)

### 5.1 Minimum Touch Target Verification
**Steps:**
1. Navigate through all views
2. Identify all interactive elements (buttons, links, etc.)
3. Measure/verify touch target sizes

**Expected Results:**
- All interactive elements meet minimum 48x48 point touch target (iPad standard)
- Buttons are easily tappable
- No elements are too small to tap accurately
- Touch targets are larger than iPhone minimum (44pt)

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 5.2 Touch Target Spacing - iPad
**Steps:**
1. Navigate through views with multiple buttons
2. Attempt to tap buttons rapidly
3. Check for accidental taps on adjacent elements
4. Test in both orientations

**Expected Results:**
- Adequate spacing between touch targets (12pt recommended padding)
- No accidental activation of adjacent elements
- Buttons are clearly separated
- Spacing works well in both orientations

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 6: Keyboard Navigation - iPad Specific

### 6.1 External Keyboard Navigation
**Steps:**
1. Connect external keyboard to iPad
2. Navigate through app using Tab key
3. Test arrow key navigation
4. Test Enter/Space to activate
5. Test Escape to dismiss

**Expected Results:**
- Tab key moves focus between interactive elements
- Arrow keys navigate within lists/grids
- Enter/Space activates focused element
- Escape dismisses modals/sheets
- Focus indicators are visible
- Navigation is logical and intuitive

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 6.2 Keyboard Shortcuts
**Steps:**
1. With external keyboard connected
2. Test keyboard shortcuts:
   - Cmd+N for new items (if implemented)
   - Cmd+F for search (if implemented)
   - Cmd+, for settings (if implemented)
3. Verify shortcuts work as expected

**Expected Results:**
- Keyboard shortcuts work correctly
- Shortcuts are discoverable
- No conflicts with system shortcuts
- Shortcuts enhance productivity

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 6.3 Focus Management
**Steps:**
1. Use external keyboard to navigate
2. Open modals and sheets
3. Test focus trapping in modals
4. Test focus return after dismissal

**Expected Results:**
- Focus is properly managed
- Modals trap focus correctly
- Focus returns to previous element after dismissal
- Focus indicators are clear and visible

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 7: iPad-Specific Layout Features

### 7.1 Split View Navigation
**Steps:**
1. Navigate to Chat view
2. Verify sidebar + detail split view
3. Test navigation between sidebar and detail
4. Test in both orientations

**Expected Results:**
- Split view is properly implemented
- Sidebar navigation works correctly
- Detail view updates when sidebar selection changes
- Layout adapts to orientation changes
- Both views are accessible

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 7.2 View Mode Toggle (Documents)
**Steps:**
1. Navigate to Documents view
2. Toggle between List and Grid views
3. Verify both modes are accessible
4. Test document selection in both modes

**Expected Results:**
- View mode toggle is accessible
- List view works correctly
- Grid view works correctly
- Both modes are fully accessible
- Selection works in both modes

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 7.3 Multi-Column Layouts
**Steps:**
1. Navigate through views that use multi-column layouts
2. Verify content organization
3. Test accessibility in multi-column views

**Expected Results:**
- Multi-column layouts are accessible
- Content is logically organized
- Navigation is intuitive
- All content is reachable

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 8: Orientation Support

### 8.1 Portrait Orientation
**Steps:**
1. Lock iPad in portrait orientation
2. Navigate through all views
3. Test all functionality

**Expected Results:**
- All views work correctly in portrait
- Layouts are optimized for portrait
- All features are accessible
- No layout issues

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 8.2 Landscape Orientation
**Steps:**
1. Lock iPad in landscape orientation
2. Navigate through all views
3. Test all functionality

**Expected Results:**
- All views work correctly in landscape
- Layouts take advantage of landscape width
- Split views work well in landscape
- All features are accessible

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 8.3 Orientation Changes
**Steps:**
1. Start app in portrait
2. Rotate to landscape
3. Rotate back to portrait
4. Verify no layout issues

**Expected Results:**
- Smooth transitions between orientations
- No layout glitches
- All content remains accessible
- Focus is maintained appropriately

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 9: Form Accessibility - iPad

### 9.1 Personal Info Editor - iPad Layout
**Steps:**
1. Navigate to Health Data → Personal Info
2. Enable VoiceOver
3. Navigate through form fields
4. Test validation messages
5. Test in both orientations

**Expected Results:**
- All form fields are accessible
- Labels are clearly announced
- Validation errors are announced
- Keyboard navigation works
- Layout is optimized for iPad

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 9.2 Blood Test Entry - iPad Layout
**Steps:**
1. Navigate to add new blood test
2. Enable VoiceOver
3. Fill out form fields
4. Test date pickers and other controls
5. Test with external keyboard

**Expected Results:**
- All form controls are accessible
- Date pickers work with VoiceOver
- Dropdown menus are accessible
- External keyboard navigation works
- Layout uses iPad space effectively

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 10: Document Management - iPad

### 10.1 Document Grid View
**Steps:**
1. Navigate to Documents view
2. Switch to Grid view
3. Enable VoiceOver
4. Navigate through grid items
5. Test selection

**Expected Results:**
- Grid items are accessible
- Navigation is logical
- Selection works correctly
- Document information is readable

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 10.2 Batch Operations
**Steps:**
1. Enter edit mode in Documents view
2. Select multiple documents
3. Test batch processing
4. Verify accessibility of batch actions

**Expected Results:**
- Edit mode is accessible
- Multi-select works correctly
- Batch actions are clearly labeled
- Progress indicators are accessible

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 11: Search and Filter - iPad

### 11.1 Search Field - iPad Layout
**Steps:**
1. Navigate to Documents view
2. Focus on search field
3. Enter search text
4. Test clear button
5. Test with external keyboard

**Expected Results:**
- Search field is properly labeled
- Search hints are clear
- Clear button is accessible
- External keyboard works for input
- Search results are announced

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 11.2 Filter Functionality - iPad
**Steps:**
1. Tap filter button
2. Navigate through filter options
3. Apply filters
4. Check active filter indicators
5. Test with external keyboard

**Expected Results:**
- Filter button state is announced
- Filter options are accessible
- Active filters are clearly indicated
- Keyboard navigation works
- Filter removal is accessible

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 12: Overall Usability - iPad

### 12.1 Complete Workflow with VoiceOver
**Steps:**
1. Complete a full workflow using only VoiceOver:
   - Add personal information
   - Add a blood test result
   - Import a document
   - Process the document
   - View results in chat
2. Note any difficulties or barriers

**Expected Results:**
- All workflows are completable with VoiceOver
- No critical barriers to usage
- Navigation is logical and intuitive
- All features are accessible
- iPad-specific features enhance usability

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 12.2 Complete Workflow with External Keyboard
**Steps:**
1. Connect external keyboard
2. Complete a full workflow using only keyboard:
   - Navigate through all tabs
   - Add data
   - Search and filter
   - Manage documents
3. Note efficiency and ease of use

**Expected Results:**
- All workflows are completable with keyboard only
- Keyboard navigation is efficient
- Shortcuts enhance productivity
- No mouse/touch required
- Focus management is correct

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test Summary

**Test Date:** _______________
**Tester Name:** _______________
**Device Model:** _______________
**iOS Version:** _______________
**External Keyboard Used:** ☐ Yes ☐ No

**Total Tests:** 12 major test areas
**Passed:** _____
**Failed:** _____

**Critical Issues Found:**
1. _________________________________________________
2. _________________________________________________
3. _________________________________________________

**iPad-Specific Issues:**
1. _________________________________________________
2. _________________________________________________
3. _________________________________________________

**Notes:**
_________________________________________________
_________________________________________________
_________________________________________________

---

## Quick Reference: VoiceOver Gestures (iPad)

- **Swipe Right:** Next element
- **Swipe Left:** Previous element
- **Double Tap:** Activate
- **Two-finger tap:** Pause/Resume VoiceOver
- **Three-finger swipe up:** Read from top
- **Three-finger swipe down:** Read from current position
- **Two-finger double tap:** Start/Stop reading
- **Two-finger scrub (zigzag):** Go back
- **Four-finger tap top of screen:** First element
- **Four-finger tap bottom of screen:** Last element

---

## Quick Reference: Keyboard Navigation

- **Tab:** Next interactive element
- **Shift+Tab:** Previous interactive element
- **Arrow Keys:** Navigate within lists/grids
- **Enter/Space:** Activate focused element
- **Escape:** Dismiss modal/sheet
- **Cmd+Tab:** Switch between apps
- **Cmd+Space:** Spotlight search

---

## Accessibility Checklist - iPad

- [ ] All interactive elements are accessible
- [ ] All text is readable at maximum Dynamic Type size
- [ ] Color contrast meets WCAG AA standards
- [ ] Haptic feedback works appropriately (lighter than iPhone)
- [ ] Touch targets meet minimum 48x48 points (iPad standard)
- [ ] VoiceOver navigation is logical
- [ ] External keyboard navigation works
- [ ] Keyboard shortcuts work (if implemented)
- [ ] Error messages are accessible
- [ ] Forms are fully accessible
- [ ] Dark mode works correctly
- [ ] Light mode works correctly
- [ ] Theme switching works automatically
- [ ] Split view navigation works
- [ ] View mode toggle is accessible
- [ ] Orientation changes work smoothly
- [ ] Grid view is accessible
- [ ] Multi-column layouts are accessible
- [ ] Focus management is correct
- [ ] iPad-specific optimizations are effective

