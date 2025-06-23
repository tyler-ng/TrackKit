import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Manages user sessions and user state
@MainActor
public class SessionManager {
    
    // MARK: - Singleton
    public static var current: SessionManager?
    
    // MARK: - Properties
    public private(set) var sessionId: String?
    public private(set) var userId: String?
    public private(set) var userProperties: [String: Any] = [:]
    public private(set) var sessionStartTime: Date?
    public private(set) var lastActivityTime: Date?
    
    private let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes
    private var sessionTimer: Timer?
    
    // MARK: - Initialization
    public init() {
        SessionManager.current = self
        setupNotifications()
        loadPersistedData()
    }
    
    deinit {
        SessionManager.current = nil
        removeNotifications()
        sessionTimer?.invalidate()
    }
    
    // MARK: - Session Management
    
    /// Start a new session
    public func startSession() async {
        let newSessionId = UUID().uuidString
        let now = Date()
        
        sessionId = newSessionId
        sessionStartTime = now
        lastActivityTime = now
        
        AppInfo.incrementSessionCount()
        AppInfo.updateLastUsed()
        
        persistSessionData()
        startSessionTimer()
        
        TrackKitLogger.info("Session started: \(newSessionId)")
        
        // Track session start event
        if let eventTracker = TrackKit.shared.eventTracker {
            let sessionEvent = SessionEvent(action: .start, properties: [
                "session_duration": 0,
                "previous_session_duration": getPreviousSessionDuration()
            ])
            await eventTracker.track(event: sessionEvent)
        }
    }
    
    /// End the current session
    public func endSession() async {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        AppInfo.addUsageTime(sessionDuration)
        
        TrackKitLogger.info("Session ended: \(sessionId), duration: \(sessionDuration)s")
        
        // Track session end event
        if let eventTracker = TrackKit.shared.eventTracker {
            let sessionEvent = SessionEvent(action: .end, properties: [
                "session_duration": sessionDuration
            ])
            await eventTracker.track(event: sessionEvent)
        }
        
        self.sessionId = nil
        self.sessionStartTime = nil
        stopSessionTimer()
        clearPersistedSessionData()
    }
    
    /// Update activity timestamp
    public func updateActivity() async {
        lastActivityTime = Date()
        persistSessionData()
    }
    
    /// Check if session has timed out
    public func checkSessionTimeout() async {
        guard let lastActivity = lastActivityTime else { return }
        
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
        if timeSinceLastActivity > sessionTimeout {
            TrackKitLogger.info("Session timed out")
            
            // Track session timeout event
            if let eventTracker = TrackKit.shared.eventTracker {
                let sessionEvent = SessionEvent(action: .timeout, properties: [
                    "inactive_duration": timeSinceLastActivity
                ])
                await eventTracker.track(event: sessionEvent)
            }
            
            await endSession()
        }
    }
    
    // MARK: - User Management
    
    /// Set user ID
    public func setUserId(_ userId: String) async {
        self.userId = userId
        persistUserData()
        TrackKitLogger.info("User ID set: \(userId)")
    }
    
    /// Set user properties
    public func setUserProperties(_ properties: [String: Any]) async {
        for (key, value) in properties {
            userProperties[key] = value
        }
        persistUserData()
        TrackKitLogger.debug("User properties updated: \(properties)")
    }
    
    /// Clear user data
    public func clearUserData() async {
        userId = nil
        userProperties.removeAll()
        clearPersistedUserData()
        TrackKitLogger.info("User data cleared")
    }
    
    /// Reset all session and user data
    public func reset() async {
        await endSession()
        await clearUserData()
        TrackKitLogger.info("Session manager reset")
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }
    
    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
    
    #if canImport(UIKit) && !os(watchOS)
    @objc private func applicationDidEnterBackground() {
        Task {
            await updateActivity()
        }
    }
    
    @objc private func applicationWillEnterForeground() {
        Task {
            await checkSessionTimeout()
            await updateActivity()
        }
    }
    
    @objc private func applicationWillTerminate() {
        Task {
            await endSession()
        }
    }
    #endif
    
    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.checkSessionTimeout()
            }
        }
    }
    
    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }
    
    // MARK: - Persistence (these can remain sync as they're just UserDefaults operations)
    
    private func persistSessionData() {
        var sessionData: [String: Any] = [:]
        
        if let sessionId = sessionId {
            sessionData["session_id"] = sessionId
        }
        
        if let sessionStartTime = sessionStartTime {
            sessionData["session_start_time"] = sessionStartTime.timeIntervalSince1970
        }
        
        if let lastActivityTime = lastActivityTime {
            sessionData["last_activity_time"] = lastActivityTime.timeIntervalSince1970
        }
        
        UserDefaults.standard.set(sessionData, forKey: "TrackKit_SessionData")
    }
    
    private func persistUserData() {
        var userData: [String: Any] = [:]
        
        if let userId = userId {
            userData["user_id"] = userId
        }
        
        userData["user_properties"] = userProperties
        
        UserDefaults.standard.set(userData, forKey: "TrackKit_UserData")
    }
    
    private func loadPersistedData() {
        // Load session data
        if let sessionData = UserDefaults.standard.dictionary(forKey: "TrackKit_SessionData") {
            sessionId = sessionData["session_id"] as? String
            
            if let startTimeInterval = sessionData["session_start_time"] as? TimeInterval {
                sessionStartTime = Date(timeIntervalSince1970: startTimeInterval)
            }
            
            if let activityTimeInterval = sessionData["last_activity_time"] as? TimeInterval {
                lastActivityTime = Date(timeIntervalSince1970: activityTimeInterval)
            }
        }
        
        // Load user data
        if let userData = UserDefaults.standard.dictionary(forKey: "TrackKit_UserData") {
            userId = userData["user_id"] as? String
            userProperties = userData["user_properties"] as? [String: Any] ?? [:]
        }
    }
    
    private func clearPersistedSessionData() {
        UserDefaults.standard.removeObject(forKey: "TrackKit_SessionData")
    }
    
    private func clearPersistedUserData() {
        UserDefaults.standard.removeObject(forKey: "TrackKit_UserData")
    }
    
    private func getPreviousSessionDuration() -> TimeInterval {
        // This could be enhanced to track previous session duration
        return 0
    }
}

// MARK: - Session Event

/// Event for session lifecycle tracking
public struct SessionEvent: Event {
    public let id: String
    public let timestamp: Date
    public let type: EventType = .session
    public let name: String
    public let properties: [String: Any]
    public let sessionId: String?
    public let userId: String?
    public let deviceInfo: [String: Any]
    public let appInfo: [String: Any]
    
    public enum Action: String {
        case start = "start"
        case end = "end"
        case timeout = "timeout"
    }
    
    public init(action: Action, properties: [String: Any] = [:]) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.name = "session_\(action.rawValue)"
        
        var allProperties = properties
        allProperties["action"] = action.rawValue
        
        self.properties = allProperties
        self.sessionId = SessionManager.current?.sessionId
        self.userId = SessionManager.current?.userId
        self.deviceInfo = DeviceInfo.current
        self.appInfo = AppInfo.current
    }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "event_id": id,
            "event_type": type.rawValue,
            "event_name": name,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "properties": properties,
            "device_info": deviceInfo,
            "app_info": appInfo
        ]
        
        if let sessionId = sessionId {
            dict["session_id"] = sessionId
        }
        
        if let userId = userId {
            dict["user_id"] = userId
        }
        
        return dict
    }
} 