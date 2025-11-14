# Accessibility Test Plan - iPhone

## Overview
This test plan verifies accessibility features on iPhone devices, ensuring the app is usable with VoiceOver, supports Dynamic Type, provides proper color contrast, and includes appropriate haptic feedback.

## Prerequisites
- iPhone device or iPhone simulator (iOS 17+)
- VoiceOver enabled
- Test with various Dynamic Type sizes
- Test in both Light and Dark modes

---

## Test 1: VoiceOver Support

### 1.1 Tab Bar Navigation
**Steps:**
1. Launch the app
2. Enable VoiceOver (Settings → Accessibility → VoiceOver → On, or triple-click side button if configured)
3. Swipe right to navigate through tab bar items
4. Listen to VoiceOver announcements

**Expected Results:**
- Each tab announces: "Health Data, button", "Documents, button", "AI Chat, button", "Settings, button"
- Each tab has a descriptive label
- Tabs are easily navigable with swipe gestures

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.2 Health Data View
**Steps:**
1. Navigate to "Health Data" tab using VoiceOver
2. Double-tap to activate
3. Swipe right to navigate through the view
4. Test the "Add Health Data" button (plus icon in navigation bar)

**Expected Results:**
- Navigation title "Health Data" is announced
- "Add Health Data" button announces: "Add Health Data, button, Menu to add new health data entries"
- Menu items are accessible when opened
- Personal info section is readable
- Blood test sections are accessible

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.3 Documents View
**Steps:**
1. Navigate to "Documents" tab
2. If documents exist, navigate through the list
3. Test search field
4. Test filter button
5. Test "Add Document" menu

**Expected Results:**
- Search field announces: "Search Documents, search field, Type to search for documents"
- Filter button announces current state (e.g., "Filter Documents, button, Filters active")
- Document items have descriptive labels including filename, type, and date
- All buttons have clear labels and hints

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.4 Chat View
**Steps:**
1. Navigate to "AI Chat" tab
2. Test message input field
3. Test send button
4. Navigate through conversation list if available

**Expected Results:**
- Chat interface elements are accessible
- Message input has proper label
- Send button is clearly labeled
- Messages are readable with VoiceOver

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 1.5 Settings View
**Steps:**
1. Navigate to "Settings" tab
2. Navigate through all settings sections
3. Test theme toggle
4. Test haptic feedback toggle

**Expected Results:**
- All settings are accessible
- Theme options are clearly labeled
- Toggles announce their current state
- Buttons have descriptive labels

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 2: Dynamic Type Support

### 2.1 Text Scaling - Smallest Size
**Steps:**
1. Go to Settings → Display & Brightness → Text Size
2. Set to smallest size
3. Return to app
4. Navigate through all main views

**Expected Results:**
- All text remains readable
- Text scales appropriately
- No text is cut off or overlapping
- Layout adapts to larger text

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 2.2 Text Scaling - Largest Size
**Steps:**
1. Go to Settings → Display & Brightness → Text Size
2. Set to largest size
3. Return to app
4. Navigate through all main views

**Expected Results:**
- All text scales to largest size
- Text remains readable
- Layout adapts without breaking
- No horizontal scrolling needed for normal content

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 2.3 Accessibility Text Sizes
**Steps:**
1. Go to Settings → Accessibility → Display & Text Size → Larger Text
2. Enable "Larger Accessibility Sizes"
3. Set to maximum size
4. Test app navigation

**Expected Results:**
- Text scales to accessibility sizes
- App remains functional
- Buttons and interactive elements remain accessible
- Layout adapts gracefully

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 3: Color Contrast and Accessibility Colors

### 3.1 Light Mode Contrast
**Steps:**
1. Set device to Light Mode (Settings → Display & Brightness)
2. Navigate through all views
3. Check text readability on all backgrounds
4. Verify button text is readable

**Expected Results:**
- Text has sufficient contrast (WCAG AA: 4.5:1 for normal text)
- Button text is clearly visible
- Status colors (success, error, warning) are distinguishable
- No text blends into background

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 3.2 Dark Mode Contrast
**Steps:**
1. Set device to Dark Mode (Settings → Display & Brightness)
2. Navigate through all views
3. Check text readability on all backgrounds
4. Verify button text is readable

**Expected Results:**
- Text has sufficient contrast in dark mode
- Button text is clearly visible
- Status colors are distinguishable
- No text blends into dark backgrounds

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 3.3 Automatic Theme Switching
**Steps:**
1. Set theme to "System" in app settings
2. Change device theme between Light and Dark
3. Verify app theme updates automatically
4. Check that colors adapt correctly

**Expected Results:**
- App theme switches automatically
- Colors adapt to new theme
- No visual glitches during transition
- All text remains readable

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 4: Haptic Feedback

### 4.1 Haptic Feedback - Enabled
**Steps:**
1. Ensure haptic feedback is enabled in Settings
2. Tap various buttons throughout the app:
   - Add buttons
   - Save buttons
   - Filter buttons
   - Menu items
3. Perform actions that trigger feedback

**Expected Results:**
- Button taps provide medium impact haptic feedback
- Success actions (save, complete) provide success haptic
- Error actions provide error haptic
- Selection changes provide selection haptic
- Feedback is consistent and appropriate

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 4.2 Haptic Feedback - Disabled
**Steps:**
1. Disable haptic feedback in app Settings
2. Perform the same actions as Test 4.1

**Expected Results:**
- No haptic feedback is provided
- App functions normally
- Visual feedback still works

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 5: Touch Target Sizes

### 5.1 Minimum Touch Target Verification
**Steps:**
1. Navigate through all views
2. Identify all interactive elements (buttons, links, etc.)
3. Measure/verify touch target sizes

**Expected Results:**
- All interactive elements meet minimum 44x44 point touch target
- Buttons are easily tappable
- No elements are too small to tap accurately
- Spacing between elements is adequate

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 5.2 Touch Target Spacing
**Steps:**
1. Navigate through views with multiple buttons
2. Attempt to tap buttons rapidly
3. Check for accidental taps on adjacent elements

**Expected Results:**
- Adequate spacing between touch targets
- No accidental activation of adjacent elements
- Buttons are clearly separated

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 6: Form Accessibility

### 6.1 Personal Info Editor
**Steps:**
1. Navigate to Health Data → Personal Info
2. Enable VoiceOver
3. Navigate through form fields
4. Test validation messages

**Expected Results:**
- All form fields are accessible
- Labels are clearly announced
- Validation errors are announced
- Keyboard navigation works

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 6.2 Blood Test Entry
**Steps:**
1. Navigate to add new blood test
2. Enable VoiceOver
3. Fill out form fields
4. Test date pickers and other controls

**Expected Results:**
- All form controls are accessible
- Date pickers work with VoiceOver
- Dropdown menus are accessible
- Save button is clearly labeled

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 7: Error Handling and Feedback

### 7.1 Error Messages
**Steps:**
1. Trigger various error conditions:
   - Network errors
   - Validation errors
   - Save failures
2. Check error message accessibility

**Expected Results:**
- Error messages are announced by VoiceOver
- Error messages are readable
- Error colors have sufficient contrast
- Recovery actions are accessible

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 8: Document Management

### 8.1 Document List Accessibility
**Steps:**
1. Navigate to Documents view
2. Enable VoiceOver
3. Navigate through document list
4. Test document selection

**Expected Results:**
- Documents have descriptive labels
- Document status is announced
- File sizes are readable
- Selection state is announced

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 8.2 Document Actions
**Steps:**
1. Select a document
2. Test available actions (process, delete, etc.)
3. Verify action buttons are accessible

**Expected Results:**
- Action buttons are clearly labeled
- Destructive actions (delete) are clearly identified
- Action hints are descriptive

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 9: Search and Filter

### 9.1 Search Field
**Steps:**
1. Navigate to Documents view
2. Focus on search field
3. Enter search text
4. Test clear button

**Expected Results:**
- Search field is properly labeled
- Search hints are clear
- Clear button is accessible
- Search results are announced

**Pass/Fail:** ☐ Pass ☐ Fail

---

### 9.2 Filter Functionality
**Steps:**
1. Tap filter button
2. Navigate through filter options
3. Apply filters
4. Check active filter indicators

**Expected Results:**
- Filter button state is announced
- Filter options are accessible
- Active filters are clearly indicated
- Filter removal is accessible

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test 10: Overall Usability

### 10.1 Complete Workflow
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

**Pass/Fail:** ☐ Pass ☐ Fail

---

## Test Summary

**Test Date:** _______________
**Tester Name:** _______________
**Device Model:** _______________
**iOS Version:** _______________

**Total Tests:** 10 major test areas
**Passed:** _____
**Failed:** _____

**Critical Issues Found:**
1. _________________________________________________
2. _________________________________________________
3. _________________________________________________

**Notes:**
_________________________________________________
_________________________________________________
_________________________________________________

---

## Quick Reference: VoiceOver Gestures

- **Swipe Right:** Next element
- **Swipe Left:** Previous element
- **Double Tap:** Activate
- **Two-finger tap:** Pause/Resume VoiceOver
- **Three-finger swipe up:** Read from top
- **Three-finger swipe down:** Read from current position
- **Two-finger double tap:** Start/Stop reading
- **Two-finger scrub (zigzag):** Go back

---

## Accessibility Checklist

- [ ] All interactive elements are accessible
- [ ] All text is readable at maximum Dynamic Type size
- [ ] Color contrast meets WCAG AA standards
- [ ] Haptic feedback works appropriately
- [ ] Touch targets meet minimum 44x44 points
- [ ] VoiceOver navigation is logical
- [ ] Error messages are accessible
- [ ] Forms are fully accessible
- [ ] Dark mode works correctly
- [ ] Light mode works correctly
- [ ] Theme switching works automatically

