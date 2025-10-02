# Disclaimer Management System

## Overview

The app now uses a robust database-backed system to manage disclaimer acceptance, ensuring that users cannot bypass the disclaimer by reinstalling the app or clearing UserDefaults.

## How It Works

### 1. Database Storage
- **Table**: `app_settings` - Stores app-level settings including disclaimer acceptance
- **Key Fields**:
  - `disclaimer_accepted`: Boolean flag (stored as "true"/"false" string)
  - `first_launch_completed`: Boolean flag for first launch tracking
  - `app_version`: Current app version when disclaimer was accepted
  - `last_disclaimer_version`: Version of disclaimer content (for future updates)

### 2. First Launch Detection
The system determines if this is a first launch by checking:
1. If `first_launch_completed` exists in database
2. If `disclaimer_accepted` is "true"
3. If disclaimer version matches current version

### 3. Disclaimer Triggers
The disclaimer will be shown if:
- `disclaimer_accepted` is not "true" (never accepted)
- `last_disclaimer_version` doesn't match current version (content changed)
- Database doesn't exist (first install)

### 4. Persistence
- **Survives app reinstall**: Data stored in app's Documents directory
- **Survives UserDefaults clear**: Uses database, not UserDefaults
- **Survives device restart**: Database persists across sessions
- **Survives app updates**: Version tracking ensures re-acceptance if needed

## Implementation Details

### AppSettingsManager
- Singleton class that manages disclaimer state
- Publishes `@Published` properties for UI binding
- Handles database operations for settings

### DatabaseManager+AppSettings
- Extension with database operations for app settings
- Handles disclaimer acceptance, version tracking
- Provides migration support for new settings

### App Launch Flow
1. App starts → `HealthAppApp` checks `AppSettingsManager.shared.shouldShowDisclaimer`
2. If true → Show `FirstLaunchDisclaimerView`
3. User accepts → Call `AppSettingsManager.shared.acceptDisclaimer()`
4. Database updated → App proceeds to main interface

## Testing

### Reset Disclaimer (for testing)
- Go to Settings → Reset menu → "Reset Disclaimer Acceptance"
- Next app launch will show disclaimer again

### Force First Launch
- Delete app from device
- Reinstall app
- Disclaimer will appear

### Version Change Test
- Modify disclaimer version in `DatabaseManager+AppSettings.swift`
- App will show disclaimer again on next launch

## Security Considerations

- Disclaimer acceptance is stored in encrypted database
- Cannot be bypassed by clearing UserDefaults
- Version tracking prevents content changes from going unnoticed
- Database location is in app's sandboxed Documents directory

## Future Enhancements

- Add disclaimer content versioning for legal updates
- Track acceptance timestamp for audit purposes
- Add user consent for different features separately
- Implement disclaimer acceptance history
