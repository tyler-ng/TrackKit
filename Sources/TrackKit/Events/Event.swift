import Foundation

/// Base protocol for all trackable events
public protocol Event {
    var id: String { get }
    var timestamp: Date { get }
    var type: EventType { get }
    var name: String { get }
    var properties: [String: Any] { get }
    var sessionId: String? { get }
    var userId: String? { get }
    var deviceInfo: [String: Any] { get }
    var appInfo: [String: Any] { get }
    
    func toDictionary() -> [String: Any]
}

/// Types of events that can be tracked
public enum EventType: String, CaseIterable {
    case view = "view"
    case button = "button_click"
    case error = "error"
    case session = "session"
    case custom = "custom"
}

/// Priority levels for event delivery
public enum EventPriority: Int, Comparable {
    case low = 1
    case normal = 2
    case high = 3
    case critical = 4
    
    public static func < (lhs: EventPriority, rhs: EventPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Base implementation of Event protocol
public struct TrackingEvent: Event {
    public let id: String
    public let timestamp: Date
    public let type: EventType
    public let name: String
    public let properties: [String: Any]
    public let sessionId: String?
    public let userId: String?
    public let deviceInfo: [String: Any]
    public let appInfo: [String: Any]
    public let priority: EventPriority
    
    public init(
        type: EventType,
        name: String,
        properties: [String: Any] = [:],
        sessionId: String? = nil,
        userId: String? = nil,
        priority: EventPriority = .normal
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.type = type
        self.name = name
        self.properties = properties
        self.sessionId = sessionId
        self.userId = userId
        self.deviceInfo = DeviceInfo.current
        self.appInfo = AppInfo.current
        self.priority = priority
    }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "event_id": id,
            "event_type": type.rawValue,
            "event_name": name,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "properties": properties,
            "device_info": deviceInfo,
            "app_info": appInfo,
            "priority": priority.rawValue
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

/// Custom event for user-defined tracking
public struct CustomEvent: Event {
    public let id: String
    public let timestamp: Date
    public let type: EventType = .custom
    public let name: String
    public let properties: [String: Any]
    public let sessionId: String?
    public let userId: String?
    public let deviceInfo: [String: Any]
    public let appInfo: [String: Any]
    
    public init(name: String, properties: [String: Any] = [:]) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.name = name
        self.properties = properties
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

/// View event for tracking screen/page views
public struct ViewEvent: Event {
    public let id: String
    public let timestamp: Date
    public let type: EventType = .view
    public let name: String
    public let properties: [String: Any]
    public let sessionId: String?
    public let userId: String?
    public let deviceInfo: [String: Any]
    public let appInfo: [String: Any]
    
    public let viewName: String
    public let duration: TimeInterval?
    
    public init(viewName: String, properties: [String: Any] = [:], duration: TimeInterval? = nil) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.name = "view_\(viewName)"
        self.viewName = viewName
        self.duration = duration
        
        var allProperties = properties
        allProperties["view_name"] = viewName
        if let duration = duration {
            allProperties["duration"] = duration
        }
        
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

/// Button event for tracking button clicks
public struct ButtonEvent: Event {
    public let id: String
    public let timestamp: Date
    public let type: EventType = .button
    public let name: String
    public let properties: [String: Any]
    public let sessionId: String?
    public let userId: String?
    public let deviceInfo: [String: Any]
    public let appInfo: [String: Any]
    
    public let buttonName: String
    public let buttonType: String?
    
    public init(buttonName: String, properties: [String: Any] = [:], buttonType: String? = nil) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.name = "button_click_\(buttonName)"
        self.buttonName = buttonName
        self.buttonType = buttonType
        
        var allProperties = properties
        allProperties["button_name"] = buttonName
        if let buttonType = buttonType {
            allProperties["button_type"] = buttonType
        }
        
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

/// Error event for tracking errors and exceptions
public struct ErrorEvent: Event {
    public let id: String
    public let timestamp: Date
    public let type: EventType = .error
    public let name: String
    public let properties: [String: Any]
    public let sessionId: String?
    public let userId: String?
    public let deviceInfo: [String: Any]
    public let appInfo: [String: Any]
    
    public let error: Error
    public let errorDescription: String
    public let stackTrace: [String]?
    
    public init(error: Error, properties: [String: Any] = [:], stackTrace: [String]? = nil) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.error = error
        self.errorDescription = error.localizedDescription
        self.stackTrace = stackTrace
        self.name = "error_\(type(of: error))"
        
        var allProperties = properties
        allProperties["error_description"] = errorDescription
        allProperties["error_domain"] = (error as NSError).domain
        allProperties["error_code"] = (error as NSError).code
        
        if let stackTrace = stackTrace {
            allProperties["stack_trace"] = stackTrace
        }
        
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

/// Session event for tracking user sessions
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
    
    public let sessionAction: SessionAction
    
    public enum SessionAction: String {
        case start = "session_start"
        case end = "session_end"
        case timeout = "session_timeout"
    }
    
    public init(action: SessionAction, properties: [String: Any] = [:]) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.sessionAction = action
        self.name = action.rawValue
        
        var allProperties = properties
        allProperties["session_action"] = action.rawValue
        
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