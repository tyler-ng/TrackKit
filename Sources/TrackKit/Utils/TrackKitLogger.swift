import Foundation
import os.log

/// Logging utility for TrackKit SDK
public struct TrackKitLogger {
    
    /// Log levels
    public enum LogLevel: Int, CaseIterable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        
        var prefix: String {
            switch self {
            case .debug: return "🔍 [DEBUG]"
            case .info: return "ℹ️ [INFO]"
            case .warning: return "⚠️ [WARNING]"
            case .error: return "❌ [ERROR]"
            }
        }
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .error
            case .error: return .fault
            }
        }
    }
    
    /// Whether debug logging is enabled
    public static var debugEnabled: Bool = false
    
    /// Minimum log level to display
    public static var minimumLogLevel: LogLevel = .info
    
    /// Custom log handler
    public static var customLogHandler: ((String, LogLevel) -> Void)?
    
    /// OSLog instance for TrackKit
    private static let osLog = OSLog(subsystem: "com.trackkit.sdk", category: "TrackKit")
    
    /// Log a message
    /// - Parameters:
    ///   - message: Message to log
    ///   - level: Log level
    ///   - file: Source file (automatically filled)
    ///   - function: Source function (automatically filled)
    ///   - line: Source line (automatically filled)
    public static func log(
        _ message: String,
        level: LogLevel,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Check if we should log this level
        guard level.rawValue >= minimumLogLevel.rawValue else { return }
        
        // Don't log debug messages unless explicitly enabled
        if level == .debug && !debugEnabled { return }
        
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedMessage = "\(level.prefix) [\(timestamp)] [\(fileName):\(line)] \(function) - \(message)"
        
        // Custom log handler takes precedence
        if let customHandler = customLogHandler {
            customHandler(formattedMessage, level)
            return
        }
        
        // Use OSLog on supported platforms
        if #available(iOS 10.0, macOS 10.12, tvOS 10.0, watchOS 3.0, *) {
            os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
        } else {
            // Fallback to print for older platforms
            print(formattedMessage)
        }
    }
    
    /// Log debug message
    public static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    /// Log info message
    public static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    /// Log warning message
    public static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    /// Log error message
    public static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    /// Log error with Error object
    public static func error(_ error: Error, file: String = #file, function: String = #function, line: Int = #line) {
        let message = "Error: \(error.localizedDescription)"
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    /// Log network request
    public static func logNetworkRequest(url: String, method: String, headers: [String: String]?) {
        guard debugEnabled else { return }
        
        var message = "Network Request: \(method) \(url)"
        if let headers = headers, !headers.isEmpty {
            let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            message += "\nHeaders: \(headerString)"
        }
        
        debug(message)
    }
    
    /// Log network response
    public static func logNetworkResponse(url: String, statusCode: Int, responseTime: TimeInterval) {
        guard debugEnabled else { return }
        
        let message = "Network Response: \(url) - Status: \(statusCode) - Time: \(String(format: "%.2f", responseTime))ms"
        debug(message)
    }
    
    /// Log event tracking
    public static func logEventTracked(eventName: String, eventType: String, properties: [String: Any]?) {
        guard debugEnabled else { return }
        
        var message = "Event Tracked: \(eventName) (\(eventType))"
        if let properties = properties, !properties.isEmpty {
            message += "\nProperties: \(properties)"
        }
        
        debug(message)
    }
    
    /// Log batch operation
    public static func logBatchOperation(operation: String, eventCount: Int) {
        guard debugEnabled else { return }
        
        let message = "Batch \(operation): \(eventCount) events"
        debug(message)
    }
} 