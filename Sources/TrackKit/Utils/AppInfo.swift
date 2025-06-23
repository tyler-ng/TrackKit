import Foundation

/// Utility class for collecting application information
public struct AppInfo {
    
    /// Current application information as a dictionary
    public static var current: [String: Any] {
        var info: [String: Any] = [:]
        
        if let bundle = Bundle.main.infoDictionary {
            info["bundle_id"] = Bundle.main.bundleIdentifier
            info["app_name"] = bundle["CFBundleDisplayName"] ?? bundle["CFBundleName"]
            info["app_version"] = bundle["CFBundleShortVersionString"]
            info["build_number"] = bundle["CFBundleVersion"]
            info["bundle_name"] = bundle["CFBundleName"]
            info["executable_name"] = bundle["CFBundleExecutable"]
        }
        
        // TrackKit SDK information
        info["sdk_name"] = "TrackKit"
        info["sdk_version"] = "1.0.0"
        
        // Runtime information
        info["launch_time"] = launchTime
        info["install_time"] = installTime
        info["update_time"] = updateTime
        
        return info
    }
    
    /// App bundle identifier
    public static var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "unknown"
    }
    
    /// App display name
    public static var displayName: String {
        if let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String {
            return displayName
        }
        if let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String {
            return bundleName
        }
        return "Unknown App"
    }
    
    /// App version string
    public static var version: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    
    /// App build number
    public static var buildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
    
    /// App launch time (when the app was started)
    private static var launchTime: String {
        return ISO8601DateFormatter().string(from: Date())
    }
    
    /// App install time (first time the app was installed)
    private static var installTime: String? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: documentsPath.path)
            if let creationDate = attributes[.creationDate] as? Date {
                return ISO8601DateFormatter().string(from: creationDate)
            }
        } catch {
            // Ignore error
        }
        
        return nil
    }
    
    /// App update time (when the app was last updated)
    private static var updateTime: String? {
        guard let bundlePath = Bundle.main.bundlePath else { return nil }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: bundlePath)
            if let modificationDate = attributes[.modificationDate] as? Date {
                return ISO8601DateFormatter().string(from: modificationDate)
            }
        } catch {
            // Ignore error
        }
        
        return nil
    }
    
    /// Check if app is running in debug mode
    public static var isDebugMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// Check if app is running in simulator
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    /// App environment (debug, release, etc.)
    public static var environment: String {
        if isDebugMode {
            return "debug"
        } else if isSimulator {
            return "simulator"
        } else {
            return "release"
        }
    }
    
    /// App architecture
    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #elseif arch(i386)
        return "i386"
        #else
        return "unknown"
        #endif
    }
    
    /// App permissions (basic check for common permissions)
    public static var permissions: [String: Bool] {
        var permissions: [String: Bool] = [:]
        
        // Camera permission
        #if canImport(AVFoundation)
        import AVFoundation
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        permissions["camera"] = cameraStatus == .authorized
        #endif
        
        // Photo library permission
        #if canImport(Photos)
        import Photos
        let photoStatus = PHPhotoLibrary.authorizationStatus()
        permissions["photos"] = photoStatus == .authorized
        #endif
        
        // Location permission
        #if canImport(CoreLocation)
        import CoreLocation
        let locationManager = CLLocationManager()
        let locationStatus = locationManager.authorizationStatus
        permissions["location"] = locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
        #endif
        
        // Notification permission
        #if canImport(UserNotifications)
        import UserNotifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            permissions["notifications"] = settings.authorizationStatus == .authorized
        }
        #endif
        
        return permissions
    }
    
    /// Memory warning count (would need to be tracked by the app)
    public static var memoryWarningCount: Int {
        return UserDefaults.standard.integer(forKey: "TrackKit_MemoryWarningCount")
    }
    
    /// Crash count (would need to be tracked by the app)
    public static var crashCount: Int {
        return UserDefaults.standard.integer(forKey: "TrackKit_CrashCount")
    }
    
    /// App usage statistics
    public static var usageStats: [String: Any] {
        let defaults = UserDefaults.standard
        return [
            "launch_count": defaults.integer(forKey: "TrackKit_LaunchCount"),
            "session_count": defaults.integer(forKey: "TrackKit_SessionCount"),
            "total_usage_time": defaults.double(forKey: "TrackKit_TotalUsageTime"),
            "last_used": defaults.object(forKey: "TrackKit_LastUsed") as? String ?? ""
        ]
    }
    
    /// Increment launch count
    internal static func incrementLaunchCount() {
        let key = "TrackKit_LaunchCount"
        let count = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(count + 1, forKey: key)
    }
    
    /// Increment session count
    internal static func incrementSessionCount() {
        let key = "TrackKit_SessionCount"
        let count = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(count + 1, forKey: key)
    }
    
    /// Record memory warning
    internal static func recordMemoryWarning() {
        let key = "TrackKit_MemoryWarningCount"
        let count = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(count + 1, forKey: key)
    }
    
    /// Record crash
    internal static func recordCrash() {
        let key = "TrackKit_CrashCount"
        let count = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(count + 1, forKey: key)
    }
    
    /// Update last used time
    internal static func updateLastUsed() {
        let key = "TrackKit_LastUsed"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(timestamp, forKey: key)
    }
    
    /// Add usage time
    internal static func addUsageTime(_ seconds: TimeInterval) {
        let key = "TrackKit_TotalUsageTime"
        let totalTime = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(totalTime + seconds, forKey: key)
    }
} 