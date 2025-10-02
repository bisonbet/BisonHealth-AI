import Foundation

extension UserDefaults {
    private enum Keys {
        static let hasAcceptedDisclaimer = "hasAcceptedDisclaimer"
        static let isFirstLaunch = "isFirstLaunch"
    }
    
    var hasAcceptedDisclaimer: Bool {
        get {
            bool(forKey: Keys.hasAcceptedDisclaimer)
        }
        set {
            set(newValue, forKey: Keys.hasAcceptedDisclaimer)
            synchronize()
        }
    }
    
    var isFirstLaunch: Bool {
        get {
            // If the key doesn't exist, it's the first launch
            if object(forKey: Keys.isFirstLaunch) == nil {
                set(false, forKey: Keys.isFirstLaunch)
                return true
            }
            return bool(forKey: Keys.isFirstLaunch)
        }
        set {
            set(newValue, forKey: Keys.isFirstLaunch)
            synchronize()
        }
    }
    
    func resetFirstLaunch() {
        removeObject(forKey: Keys.isFirstLaunch)
        removeObject(forKey: Keys.hasAcceptedDisclaimer)
        synchronize()
    }
}
