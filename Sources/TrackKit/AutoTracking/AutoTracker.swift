import Foundation
import UIKit

/// Main auto-tracking coordinator for iOS
public class AutoTracker {
    
    // MARK: - Properties
    private let eventTracker: EventTracker
    private var isAutoTrackingEnabled = false
    
    internal var viewTracker: ViewControllerTracker?
    internal var buttonTracker: ButtonTracker?
    internal var errorTracker: ErrorTracker?
    
    // MARK: - Initialization
    public init(eventTracker: EventTracker) {
        self.eventTracker = eventTracker
    }
    
    deinit {
        stopAutoTracking()
    }
    
    // MARK: - Public Methods
    
    /// Start automatic tracking
    public func startAutoTracking() {
        guard !isAutoTrackingEnabled else {
            TrackKitLogger.warning("Auto-tracking is already enabled")
            return
        }
        
        isAutoTrackingEnabled = true
        
        // Initialize trackers
        viewTracker = ViewControllerTracker(eventTracker: eventTracker)
        buttonTracker = ButtonTracker(eventTracker: eventTracker)
        errorTracker = ErrorTracker(eventTracker: eventTracker)
        
        // Start tracking
        viewTracker?.startTracking()
        buttonTracker?.startTracking()
        errorTracker?.startTracking()
        
        TrackKitLogger.info("Auto-tracking started")
    }
    
    /// Stop automatic tracking
    public func stopAutoTracking() {
        guard isAutoTrackingEnabled else {
            TrackKitLogger.warning("Auto-tracking is not enabled")
            return
        }
        
        isAutoTrackingEnabled = false
        
        // Stop tracking
        viewTracker?.stopTracking()
        buttonTracker?.stopTracking()
        errorTracker?.stopTracking()
        
        // Clean up
        viewTracker = nil
        buttonTracker = nil
        errorTracker = nil
        
        TrackKitLogger.info("Auto-tracking stopped")
    }
    
    /// Check if auto-tracking is enabled
    public var isEnabled: Bool {
        return isAutoTrackingEnabled
    }
    
    /// Enable/disable specific auto-tracking features
    public func setViewTrackingEnabled(_ enabled: Bool) {
        if enabled {
            viewTracker?.startTracking()
        } else {
            viewTracker?.stopTracking()
        }
    }
    
    public func setButtonTrackingEnabled(_ enabled: Bool) {
        if enabled {
            buttonTracker?.startTracking()
        } else {
            buttonTracker?.stopTracking()
        }
    }
    
    public func setErrorTrackingEnabled(_ enabled: Bool) {
        if enabled {
            errorTracker?.startTracking()
        } else {
            errorTracker?.stopTracking()
        }
    }
    
    /// Add view controllers to ignore for tracking
    public func ignoreViewControllers(_ viewControllerClasses: [UIViewController.Type]) {
        viewTracker?.ignoreViewControllers(viewControllerClasses)
    }
    
    /// Add view controller names to ignore for tracking
    public func ignoreViewControllerNames(_ names: [String]) {
        viewTracker?.ignoreViewControllerNames(names)
    }
    
    /// Get auto-tracking statistics
    public var statistics: AutoTrackingStatistics {
        return AutoTrackingStatistics(
            viewEventsTracked: viewTracker?.eventsTracked ?? 0,
            buttonEventsTracked: buttonTracker?.eventsTracked ?? 0,
            errorEventsTracked: errorTracker?.eventsTracked ?? 0,
            isEnabled: isAutoTrackingEnabled
        )
    }
}

// MARK: - Auto-Tracking Statistics

/// Statistics about auto-tracking performance
public struct AutoTrackingStatistics {
    public let viewEventsTracked: Int
    public let buttonEventsTracked: Int
    public let errorEventsTracked: Int
    public let isEnabled: Bool
    
    public var totalEventsTracked: Int {
        return viewEventsTracked + buttonEventsTracked + errorEventsTracked
    }
} 