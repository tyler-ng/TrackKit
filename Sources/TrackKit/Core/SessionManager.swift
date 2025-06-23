import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Manages user sessions and user state
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
    private let queue = DispatchQueue(label: "com.trackkit.session", qos: .utility)
    
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
    public func startSession() {
        queue.async { [weak self] in
            let newSessionId = UUID().uuidString
            let now = Date()
            
            self?.sessionId = newSessionId
            self?.sessionStartTime = now
            self?.lastActivityTime = now
            
            AppInfo.incrementSessionCount()
            AppInfo.updateLastUsed()
            
            self?.persistSessionData()
            self?.startSessionTimer()
            
            TrackKitLogger.info("Session started: \(newSessionId)")
            
            // Track session start event
            DispatchQueue.main.async {
                if let eventTracker = TrackKit.shared.eventTracker {
                    let sessionEvent = SessionEvent(action: .start, properties: [
                        "session_duration": 0,
                        "previous_session_duration": self?.getPreviousSessionDuration() ?? 0
                    ])
                    eventTracker.track(event: sessionEvent)
                }
            }
        }
    }
    
    /// End the current session
    public func endSession() {
        queue.async { [weak self] in
            guard let sessionId = self?.sessionId,
                  let startTime = self?.sessionStartTime else { return }
            
            let sessionDuration = Date().timeIntervalSince(startTime)
            AppInfo.addUsageTime(sessionDuration)
            
            TrackKitLogger.info("Session ended: \(sessionId), duration: \(sessionDuration)s")
            
            // Track session end event
            DispatchQueue.main.async {
                if let eventTracker = TrackKit.shared.eventTracker {
                    let sessionEvent = SessionEvent(action: .end, properties: [
                        "session_duration": sessionDuration
                    ])
                    eventTracker.track(event: sessionEvent)
                }
            }
            
            self?.sessionId = nil
            self?.sessionStartTime = nil
            self?.stopSessionTimer()
            self?.clearPersistedSessionData()
        }
    }
    
    /// Update activity timestamp
    public func updateActivity() {
        queue.async { [weak self] in
            self?.lastActivityTime = Date()
            self?.persistSessionData()
        }
    }
    
    /// Check if session has timed out
    public func checkSessionTimeout() {
        queue.async { [weak self] in
            guard let lastActivity = self?.lastActivityTime else { return }
            
            let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
            if timeSinceLastActivity > (self?.sessionTimeout ?? 1800) {
                TrackKitLogger.info("Session timed out")
                
                // Track session timeout event
                DispatchQueue.main.async {
                    if let eventTracker = TrackKit.shared.eventTracker {
                        let sessionEvent = SessionEvent(action: .timeout, properties: [
                            "inactive_duration": timeSinceLastActivity
                        ])
                        eventTracker.track(event: sessionEvent)
                    }
                }
                
                self?.endSession()
            }
        }
    }
    
    // MARK: - User Management
    
    /// Set user ID
    public func setUserId(_ userId: String) {
        queue.async { [weak self] in
            self?.userId = userId
            self?.persistUserData()
            TrackKitLogger.info("User ID set: \(userId)")
        }
    }
    
    /// Set user properties
    public func setUserProperties(_ properties: [String: Any]) {
        queue.async { [weak self] in
            for (key, value) in properties {
                self?.userProperties[key] = value
            }
            self?.persistUserData()
            TrackKitLogger.debug("User properties updated: \(properties)")
        }
    }
    
    /// Clear user data
    public func clearUserData() {
        queue.async { [weak self] in
            self?.userId = nil
            self?.userProperties.removeAll()
            self?.clearPersistedUserData()
            TrackKitLogger.info("User data cleared")
        }
    }
    
    /// Reset all session and user data
    public func reset() {
        queue.async { [weak self] in
            self?.endSession()
            self?.clearUserData()
            TrackKitLogger.info("Session manager reset")
        }
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
        TrackKitLogger.debug("App entered background")
        updateActivity()
    }
    
    @objc private func applicationWillEnterForeground() {
        TrackKitLogger.debug("App will enter foreground")
        checkSessionTimeout()
        updateActivity()
    }
    
    @objc private func applicationWillTerminate() {
        TrackKitLogger.debug("App will terminate")
        endSession()
    }
    #endif
    
    private func startSessionTimer() {
        stopSessionTimer()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkSessionTimeout()
        }
    }
    
    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }
    
    // MARK: - Persistence
    
    private func persistSessionData() {
        let defaults = UserDefaults.standard
        defaults.set(sessionId, forKey: "TrackKit_SessionId")
        defaults.set(sessionStartTime, forKey: "TrackKit_SessionStartTime")
        defaults.set(lastActivityTime, forKey: "TrackKit_LastActivityTime")
    }
    
    private func persistUserData() {
        let defaults = UserDefaults.standard
        defaults.set(userId, forKey: "TrackKit_UserId")
        defaults.set(userProperties, forKey: "TrackKit_UserProperties")
    }
    
    private func loadPersistedData() {
        let defaults = UserDefaults.standard
        
        // Load session data
        sessionId = defaults.string(forKey: "TrackKit_SessionId")
        sessionStartTime = defaults.object(forKey: "TrackKit_SessionStartTime") as? Date
        lastActivityTime = defaults.object(forKey: "TrackKit_LastActivityTime") as? Date
        
        // Load user data
        userId = defaults.string(forKey: "TrackKit_UserId")
        if let properties = defaults.dictionary(forKey: "TrackKit_UserProperties") {
            userProperties = properties
        }
        
        // Check if session is still valid
        if let lastActivity = lastActivityTime {
            let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
            if timeSinceLastActivity > sessionTimeout {
                // Session expired, clear it
                clearPersistedSessionData()
                sessionId = nil
                sessionStartTime = nil
                lastActivityTime = nil
            }
        }
    }
    
    private func clearPersistedSessionData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "TrackKit_SessionId")
        defaults.removeObject(forKey: "TrackKit_SessionStartTime")
        defaults.removeObject(forKey: "TrackKit_LastActivityTime")
    }
    
    private func clearPersistedUserData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "TrackKit_UserId")
        defaults.removeObject(forKey: "TrackKit_UserProperties")
    }
    
    private func getPreviousSessionDuration() -> TimeInterval {
        return UserDefaults.standard.double(forKey: "TrackKit_PreviousSessionDuration")
    }
    
    // MARK: - Session Info
    
    /// Get current session duration
    public var sessionDuration: TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    /// Check if user is in an active session
    public var hasActiveSession: Bool {
        return sessionId != nil && sessionStartTime != nil
    }
    
    /// Get session info as dictionary
    public var sessionInfo: [String: Any] {
        var info: [String: Any] = [:]
        
        if let sessionId = sessionId {
            info["session_id"] = sessionId
        }
        
        if let userId = userId {
            info["user_id"] = userId
        }
        
        if let startTime = sessionStartTime {
            info["session_start_time"] = ISO8601DateFormatter().string(from: startTime)
            info["session_duration"] = Date().timeIntervalSince(startTime)
        }
        
        if !userProperties.isEmpty {
            info["user_properties"] = userProperties
        }
        
        return info
    }
} 