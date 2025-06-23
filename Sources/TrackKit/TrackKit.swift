import Foundation
import UIKit

/// Main TrackKit SDK class - Public interface for event tracking
@MainActor
public final class TrackKit {
    
    // MARK: - Singleton
    public static let shared = TrackKit()
    private init() {}
    
    // MARK: - Properties
    private var configuration: TrackKitConfiguration?
    private var eventTracker: EventTracker?
    private var sessionManager: SessionManager?
    private var autoTracker: AutoTracker?
    private var isConfigured = false
    
    // MARK: - Configuration
    
    /// Configure TrackKit with basic settings
    /// - Parameters:
    ///   - apiKey: Your API key
    ///   - endpoint: Your backend endpoint URL
    public static func configure(apiKey: String, endpoint: String) async {
        let config = TrackKitConfiguration(apiKey: apiKey, baseURL: endpoint)
        await configure(with: config)
    }
    
    /// Configure TrackKit with custom endpoints
    /// - Parameters:
    ///   - apiKey: Your API key
    ///   - baseURL: Base URL for your API
    ///   - singleEventEndpoint: Endpoint for single events
    ///   - batchEndpoint: Endpoint for batch events
    public static func configureWithCustomEndpoints(
        apiKey: String,
        baseURL: String,
        singleEventEndpoint: String = "/events",
        batchEndpoint: String = "/events/batch"
    ) async {
        var config = TrackKitConfiguration(apiKey: apiKey, baseURL: baseURL)
        config.endpoints = .custom(
            singleEvent: singleEventEndpoint,
            batchEvents: batchEndpoint
        )
        await configure(with: config)
    }
    
    /// Configure TrackKit with full configuration
    /// - Parameter configuration: Complete configuration object
    public static func configure(with configuration: TrackKitConfiguration) async {
        await shared.setupSDK(with: configuration)
    }
    
    private func setupSDK(with configuration: TrackKitConfiguration) async {
        self.configuration = configuration
        
        // Initialize core components
        self.sessionManager = SessionManager()
        self.eventTracker = EventTracker(configuration: configuration, sessionManager: sessionManager!)
        
        if configuration.autoTrackingEnabled {
            self.autoTracker = AutoTracker(eventTracker: eventTracker!)
            await self.autoTracker?.startAutoTracking()
        }
        
        self.isConfigured = true
        
        // Start session
        await sessionManager?.startSession()
        
        TrackKitLogger.log("TrackKit configured successfully", level: .info)
    }
    
    // MARK: - User Management
    
    /// Set the user ID for tracking
    /// - Parameter userId: Unique identifier for the user
    public static func setUserId(_ userId: String) async {
        await shared.sessionManager?.setUserId(userId)
    }
    
    /// Set user properties
    /// - Parameter properties: Dictionary of user properties
    public static func setUserProperties(_ properties: [String: Any]) async {
        await shared.sessionManager?.setUserProperties(properties)
    }
    
    // MARK: - Event Tracking
    
    /// Track a custom event
    /// - Parameters:
    ///   - event: Event name
    ///   - properties: Optional event properties
    public static func track(event: String, properties: [String: Any]? = nil) async {
        guard shared.isConfigured else {
            TrackKitLogger.log("TrackKit not configured. Call configure() first.", level: .error)
            return
        }
        
        let trackingEvent = CustomEvent(
            name: event,
            properties: properties ?? [:]
        )
        
        await shared.eventTracker?.track(event: trackingEvent)
    }
    
    /// Track a view event
    /// - Parameters:
    ///   - viewName: Name of the view
    ///   - properties: Optional view properties
    public static func trackView(_ viewName: String, properties: [String: Any]? = nil) async {
        guard shared.isConfigured else {
            TrackKitLogger.log("TrackKit not configured. Call configure() first.", level: .error)
            return
        }
        
        let viewEvent = ViewEvent(
            viewName: viewName,
            properties: properties ?? [:]
        )
        
        await shared.eventTracker?.track(event: viewEvent)
    }
    
    /// Track a button click event
    /// - Parameters:
    ///   - buttonName: Name or identifier of the button
    ///   - properties: Optional button properties
    public static func trackButton(_ buttonName: String, properties: [String: Any]? = nil) async {
        guard shared.isConfigured else {
            TrackKitLogger.log("TrackKit not configured. Call configure() first.", level: .error)
            return
        }
        
        let buttonEvent = ButtonEvent(
            buttonName: buttonName,
            properties: properties ?? [:]
        )
        
        await shared.eventTracker?.track(event: buttonEvent)
    }
    
    /// Track an error event
    /// - Parameters:
    ///   - error: The error to track
    ///   - properties: Optional error properties
    public static func trackError(_ error: Error, properties: [String: Any]? = nil) async {
        guard shared.isConfigured else {
            TrackKitLogger.log("TrackKit not configured. Call configure() first.", level: .error)
            return
        }
        
        let errorEvent = ErrorEvent(
            error: error,
            properties: properties ?? [:]
        )
        
        await shared.eventTracker?.track(event: errorEvent)
    }
    
    // MARK: - Control Methods
    
    /// Enable or disable auto-tracking
    /// - Parameter enabled: Whether auto-tracking should be enabled
    public static func enableAutoTracking(_ enabled: Bool) async {
        if enabled && shared.autoTracker == nil {
            shared.autoTracker = AutoTracker(eventTracker: shared.eventTracker!)
            await shared.autoTracker?.startAutoTracking()
        } else if !enabled {
            await shared.autoTracker?.stopAutoTracking()
            shared.autoTracker = nil
        }
    }
    
    /// Flush all pending events immediately
    public static func flush() async {
        await shared.eventTracker?.flush()
    }
    
    /// Reset the SDK state (clear user data, events, etc.)
    public static func reset() async {
        await shared.eventTracker?.reset()
        await shared.sessionManager?.reset()
    }
    
    /// Set batch size for event batching
    /// - Parameter size: Number of events per batch
    public static func setBatchSize(_ size: Int) async {
        await shared.eventTracker?.setBatchSize(size)
    }
    
    /// Set flush interval for automatic event sending
    /// - Parameter interval: Time interval in seconds
    public static func setFlushInterval(_ interval: TimeInterval) async {
        await shared.eventTracker?.setFlushInterval(interval)
    }
    
    /// Set event delivery delegate
    /// - Parameter delegate: Delegate to receive delivery notifications
    public static func setDeliveryDelegate(_ delegate: EventDeliveryDelegate) async {
        await shared.eventTracker?.setDeliveryDelegate(delegate)
    }
    
    // MARK: - Auto-Tracking Control
    
    /// Control specific auto-tracking features
    /// - Parameter enabled: Whether view tracking should be enabled
    public static func setViewTrackingEnabled(_ enabled: Bool) async {
        await shared.autoTracker?.setViewTrackingEnabled(enabled)
    }
    
    /// Control button tracking
    /// - Parameter enabled: Whether button tracking should be enabled
    public static func setButtonTrackingEnabled(_ enabled: Bool) async {
        await shared.autoTracker?.setButtonTrackingEnabled(enabled)
    }
    
    /// Control error tracking
    /// - Parameter enabled: Whether error tracking should be enabled
    public static func setErrorTrackingEnabled(_ enabled: Bool) async {
        await shared.autoTracker?.setErrorTrackingEnabled(enabled)
    }
    
    /// Add view controllers to ignore for tracking
    /// - Parameter viewControllerClasses: Array of view controller types to ignore
    public static func ignoreViewControllers(_ viewControllerClasses: [UIViewController.Type]) async {
        await shared.autoTracker?.ignoreViewControllers(viewControllerClasses)
    }
    
    /// Add view controller names to ignore for tracking
    /// - Parameter names: Array of view controller names to ignore
    public static func ignoreViewControllerNames(_ names: [String]) async {
        await shared.autoTracker?.ignoreViewControllerNames(names)
    }
    
    // MARK: - Information
    
    /// Check if TrackKit is configured and ready
    public static var isConfigured: Bool {
        return shared.isConfigured
    }
    
    /// Get SDK version
    public static var version: String {
        return "1.0.0"
    }
    
    /// Get auto-tracking statistics
    public static var autoTrackingStatistics: AutoTrackingStatistics? {
        return shared.autoTracker?.statistics
    }
    
    /// Cancel all ongoing operations
    public static func cancelAllOperations() async {
        await shared.eventTracker?.cancelAllOperations()
    }
} 