import Foundation
import UIKit

/// Tracks errors and exceptions automatically
internal class ErrorTracker {
    
    // MARK: - Properties
    private let eventTracker: EventTracker
    private var isTracking = false
    private var eventsTrackedCount = 0
    
    private var previousExceptionHandler: NSUncaughtExceptionHandler?
    
    // MARK: - Initialization
    init(eventTracker: EventTracker) {
        self.eventTracker = eventTracker
    }
    
    deinit {
        stopTracking()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking errors and exceptions
    func startTracking() {
        guard !isTracking else { return }
        
        isTracking = true
        setupExceptionHandler()
        setupSignalHandler()
        
        TrackKitLogger.debug("Error tracking started")
    }
    
    /// Stop tracking errors and exceptions
    func stopTracking() {
        guard isTracking else { return }
        
        isTracking = false
        restoreExceptionHandler()
        
        TrackKitLogger.debug("Error tracking stopped")
    }
    
    /// Get number of events tracked
    var eventsTracked: Int {
        return eventsTrackedCount
    }
    
    /// Manually track an error
    func trackError(_ error: Error, properties: [String: Any] = [:]) {
        guard isTracking else { return }
        
        var allProperties = properties
        allProperties["manual_error"] = true
        allProperties["error_tracking_enabled"] = isTracking
        
        let errorEvent = ErrorEvent(error: error, properties: allProperties)
        eventTracker.track(event: errorEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Manually tracked error: \(error.localizedDescription)")
    }
    
    // MARK: - Private Methods
    
    private func setupExceptionHandler() {
        // Store the previous handler
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        
        // Set our handler
        NSSetUncaughtExceptionHandler { [weak self] exception in
            self?.handleUncaughtException(exception)
            
            // Call the previous handler if it exists
            if let previousHandler = self?.previousExceptionHandler {
                previousHandler(exception)
            }
        }
    }
    
    private func restoreExceptionHandler() {
        NSSetUncaughtExceptionHandler(previousExceptionHandler)
        previousExceptionHandler = nil
    }
    
    private func setupSignalHandler() {
        // Handle common crash signals
        let signals = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE]
        
        for sig in signals {
            signal(sig) { [weak self] signal in
                self?.handleSignal(signal)
            }
        }
    }
    
    private func handleUncaughtException(_ exception: NSException) {
        guard isTracking else { return }
        
        let error = NSError(
            domain: "TrackKitUncaughtException",
            code: 0,
            userInfo: [
                NSLocalizedDescriptionKey: exception.reason ?? "Unknown exception",
                "exception_name": exception.name.rawValue,
                "exception_reason": exception.reason ?? "",
                "exception_user_info": exception.userInfo ?? [:]
            ]
        )
        
        var properties: [String: Any] = [
            "exception_type": "NSException",
            "exception_name": exception.name.rawValue,
            "exception_reason": exception.reason ?? "",
            "call_stack_symbols": exception.callStackSymbols,
            "call_stack_return_addresses": exception.callStackReturnAddresses.map { $0.intValue },
            "crash_type": "uncaught_exception"
        ]
        
        // Add app state information
        properties.merge(getAppStateProperties()) { _, new in new }
        
        let errorEvent = ErrorEvent(
            error: error,
            properties: properties,
            stackTrace: exception.callStackSymbols
        )
        
        // Send immediately as this is critical
        eventTracker.track(event: errorEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.error("Tracked uncaught exception: \(exception.name.rawValue)")
        
        // Force flush to ensure the error is sent
        DispatchQueue.main.async {
            TrackKit.flush()
        }
    }
    
    private func handleSignal(_ signal: Int32) {
        guard isTracking else { return }
        
        let signalName = getSignalName(signal)
        
        let error = NSError(
            domain: "TrackKitSignalError",
            code: Int(signal),
            userInfo: [
                NSLocalizedDescriptionKey: "Signal \(signal) (\(signalName)) received",
                "signal_number": signal,
                "signal_name": signalName
            ]
        )
        
        var properties: [String: Any] = [
            "exception_type": "Signal",
            "signal_number": signal,
            "signal_name": signalName,
            "crash_type": "signal"
        ]
        
        // Add app state information
        properties.merge(getAppStateProperties()) { _, new in new }
        
        // Get stack trace
        let stackTrace = Thread.callStackSymbols
        
        let errorEvent = ErrorEvent(
            error: error,
            properties: properties,
            stackTrace: stackTrace
        )
        
        // Send immediately as this is critical
        eventTracker.track(event: errorEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.error("Tracked signal: \(signal) (\(signalName))")
        
        // Force flush to ensure the error is sent
        DispatchQueue.main.async {
            TrackKit.flush()
        }
    }
    
    private func getSignalName(_ signal: Int32) -> String {
        switch signal {
        case SIGABRT: return "SIGABRT"
        case SIGILL: return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE: return "SIGFPE"
        case SIGBUS: return "SIGBUS"
        case SIGPIPE: return "SIGPIPE"
        case SIGTERM: return "SIGTERM"
        case SIGKILL: return "SIGKILL"
        default: return "UNKNOWN"
        }
    }
    
    private func getAppStateProperties() -> [String: Any] {
        var properties: [String: Any] = [:]
        
        // App state
        properties["app_state"] = UIApplication.shared.applicationState.rawValue
        properties["app_state_description"] = getApplicationStateDescription(UIApplication.shared.applicationState)
        
        // Memory information
        properties["memory_usage"] = DeviceInfo.memoryUsage
        properties["available_memory"] = DeviceInfo.availableDiskSpace
        
        // Current view controller
        if let topViewController = getTopViewController() {
            properties["current_view_controller"] = String(describing: type(of: topViewController))
        }
        
        // Thread information
        properties["is_main_thread"] = Thread.isMainThread
        properties["thread_count"] = ProcessInfo.processInfo.activeProcessorCount
        
        // Time information
        properties["crash_time"] = ISO8601DateFormatter().string(from: Date())
        properties["app_launch_time"] = AppInfo.current["launch_time"]
        
        return properties
    }
    
    private func getApplicationStateDescription(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
    
    private func getTopViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            return nil
        }
        
        return getTopViewController(from: rootViewController)
    }
    
    private func getTopViewController(from viewController: UIViewController) -> UIViewController {
        if let presentedViewController = viewController.presentedViewController {
            return getTopViewController(from: presentedViewController)
        }
        
        if let navigationController = viewController as? UINavigationController,
           let topViewController = navigationController.topViewController {
            return getTopViewController(from: topViewController)
        }
        
        if let tabBarController = viewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return getTopViewController(from: selectedViewController)
        }
        
        return viewController
    }
}

// MARK: - Error Tracking Extensions

extension ErrorTracker {
    
    /// Track network errors
    func trackNetworkError(_ error: Error, url: String, statusCode: Int?, properties: [String: Any] = [:]) {
        guard isTracking else { return }
        
        var allProperties = properties
        allProperties["error_type"] = "network"
        allProperties["url"] = url
        allProperties["status_code"] = statusCode
        allProperties["is_network_error"] = true
        
        let errorEvent = ErrorEvent(error: error, properties: allProperties)
        eventTracker.track(event: errorEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked network error: \(error.localizedDescription)")
    }
    
    /// Track parsing errors
    func trackParsingError(_ error: Error, data: String?, properties: [String: Any] = [:]) {
        guard isTracking else { return }
        
        var allProperties = properties
        allProperties["error_type"] = "parsing"
        allProperties["data"] = data
        allProperties["is_parsing_error"] = true
        
        let errorEvent = ErrorEvent(error: error, properties: allProperties)
        eventTracker.track(event: errorEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked parsing error: \(error.localizedDescription)")
    }
    
    /// Track custom application errors
    func trackApplicationError(_ error: Error, context: String, properties: [String: Any] = [:]) {
        guard isTracking else { return }
        
        var allProperties = properties
        allProperties["error_type"] = "application"
        allProperties["context"] = context
        allProperties["is_application_error"] = true
        
        let errorEvent = ErrorEvent(error: error, properties: allProperties)
        eventTracker.track(event: errorEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked application error: \(error.localizedDescription)")
    }
} 