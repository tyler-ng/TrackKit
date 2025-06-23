import Foundation
import UIKit

/// Tracks UIViewController appearances automatically using method swizzling
internal class ViewControllerTracker {
    
    // MARK: - Properties
    private let eventTracker: EventTracker
    private var isTracking = false
    private var eventsTrackedCount = 0
    
    private var ignoredViewControllerClasses: Set<String> = []
    private var ignoredViewControllerNames: Set<String> = []
    
    // Track view timing
    private var viewAppearanceTimes: [String: Date] = [:]
    
    // MARK: - Initialization
    init(eventTracker: EventTracker) {
        self.eventTracker = eventTracker
        setupDefaultIgnoredViewControllers()
    }
    
    deinit {
        stopTracking()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking view controller appearances
    func startTracking() {
        guard !isTracking else { return }
        
        isTracking = true
        swizzleViewDidAppear()
        swizzleViewDidDisappear()
        
        TrackKitLogger.debug("View controller tracking started")
    }
    
    /// Stop tracking view controller appearances
    func stopTracking() {
        guard isTracking else { return }
        
        isTracking = false
        // Note: We don't unswizzle methods to avoid potential crashes
        // The swizzled methods will check isTracking flag
        
        TrackKitLogger.debug("View controller tracking stopped")
    }
    
    /// Add view controller classes to ignore
    func ignoreViewControllers(_ viewControllerClasses: [UIViewController.Type]) {
        for vcClass in viewControllerClasses {
            ignoredViewControllerClasses.insert(String(describing: vcClass))
        }
    }
    
    /// Add view controller names to ignore
    func ignoreViewControllerNames(_ names: [String]) {
        ignoredViewControllerNames.formUnion(names)
    }
    
    /// Get number of events tracked
    var eventsTracked: Int {
        return eventsTrackedCount
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultIgnoredViewControllers() {
        // Ignore common system view controllers
        ignoredViewControllerNames = [
            "UINavigationController",
            "UITabBarController",
            "UISplitViewController",
            "UIPageViewController",
            "UIAlertController",
            "UIActivityViewController",
            "UIDocumentPickerViewController",
            "UIImagePickerController",
            "MFMailComposeViewController",
            "MFMessageComposeViewController",
            "UICloudSharingController",
            "_UIRemoteViewController",
            "SFSafariViewController"
        ]
    }
    
    private func swizzleViewDidAppear() {
        let originalSelector = #selector(UIViewController.viewDidAppear(_:))
        let swizzledSelector = #selector(UIViewController.tk_viewDidAppear(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector) else {
            TrackKitLogger.error("Failed to get methods for viewDidAppear swizzling")
            return
        }
        
        let didAddMethod = class_addMethod(
            UIViewController.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        
        if didAddMethod {
            class_replaceMethod(
                UIViewController.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    private func swizzleViewDidDisappear() {
        let originalSelector = #selector(UIViewController.viewDidDisappear(_:))
        let swizzledSelector = #selector(UIViewController.tk_viewDidDisappear(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector) else {
            TrackKitLogger.error("Failed to get methods for viewDidDisappear swizzling")
            return
        }
        
        let didAddMethod = class_addMethod(
            UIViewController.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        
        if didAddMethod {
            class_replaceMethod(
                UIViewController.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    @objc private func handleViewDidAppear(_ viewController: UIViewController, animated: Bool) {
        guard isTracking else { return }
        
        let viewControllerName = String(describing: type(of: viewController))
        
        // Check if this view controller should be ignored
        if shouldIgnoreViewController(viewController, name: viewControllerName) {
            return
        }
        
        // Record appearance time for duration calculation
        let viewControllerKey = "\(Unmanaged.passUnretained(viewController).toOpaque())"
        viewAppearanceTimes[viewControllerKey] = Date()
        
        // Create view event
        let properties = extractViewControllerProperties(viewController)
        let viewEvent = ViewEvent(viewName: viewControllerName, properties: properties)
        
        // Track the event
        eventTracker.track(event: viewEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked view appearance: \(viewControllerName)")
    }
    
    @objc private func handleViewDidDisappear(_ viewController: UIViewController, animated: Bool) {
        guard isTracking else { return }
        
        let viewControllerName = String(describing: type(of: viewController))
        
        // Check if this view controller should be ignored
        if shouldIgnoreViewController(viewController, name: viewControllerName) {
            return
        }
        
        let viewControllerKey = "\(Unmanaged.passUnretained(viewController).toOpaque())"
        
        // Calculate duration if we have appearance time
        var duration: TimeInterval? = nil
        if let appearanceTime = viewAppearanceTimes[viewControllerKey] {
            duration = Date().timeIntervalSince(appearanceTime)
            viewAppearanceTimes.removeValue(forKey: viewControllerKey)
        }
        
        // Create view event with duration
        var properties = extractViewControllerProperties(viewController)
        properties["view_action"] = "disappear"
        
        let viewEvent = ViewEvent(
            viewName: viewControllerName,
            properties: properties,
            duration: duration
        )
        
        // Track the event
        eventTracker.track(event: viewEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked view disappearance: \(viewControllerName), duration: \(duration ?? 0)")
    }
    
    private func shouldIgnoreViewController(_ viewController: UIViewController, name: String) -> Bool {
        // Check if class is in ignored list
        if ignoredViewControllerClasses.contains(name) {
            return true
        }
        
        // Check if name is in ignored list
        if ignoredViewControllerNames.contains(name) {
            return true
        }
        
        // Ignore private/system view controllers
        if name.hasPrefix("_") || name.hasPrefix("UI") && !name.contains("ViewController") {
            return true
        }
        
        // Check if it's presented modally from a system controller
        if let presentingVC = viewController.presentingViewController {
            let presentingName = String(describing: type(of: presentingVC))
            if ignoredViewControllerNames.contains(presentingName) {
                return true
            }
        }
        
        return false
    }
    
    private func extractViewControllerProperties(_ viewController: UIViewController) -> [String: Any] {
        var properties: [String: Any] = [:]
        
        // Basic properties
        properties["view_controller_class"] = String(describing: type(of: viewController))
        properties["title"] = viewController.title
        properties["modal_presentation_style"] = viewController.modalPresentationStyle.rawValue
        properties["modal_transition_style"] = viewController.modalTransitionStyle.rawValue
        
        // Navigation properties
        if let navigationController = viewController.navigationController {
            properties["is_in_navigation_controller"] = true
            properties["navigation_stack_depth"] = navigationController.viewControllers.count
            properties["is_root_view_controller"] = navigationController.viewControllers.first === viewController
        } else {
            properties["is_in_navigation_controller"] = false
        }
        
        // Tab bar properties
        if let tabBarController = viewController.tabBarController {
            properties["is_in_tab_bar_controller"] = true
            properties["tab_index"] = tabBarController.selectedIndex
            properties["total_tabs"] = tabBarController.viewControllers?.count ?? 0
        } else {
            properties["is_in_tab_bar_controller"] = false
        }
        
        // Presentation properties
        properties["is_presented"] = viewController.presentingViewController != nil
        properties["is_presenting"] = viewController.presentedViewController != nil
        
        // View properties
        if viewController.isViewLoaded {
            properties["view_bounds"] = NSStringFromCGRect(viewController.view.bounds)
            properties["view_alpha"] = viewController.view.alpha
            properties["view_hidden"] = viewController.view.isHidden
        }
        
        return properties
    }
}

// MARK: - UIViewController Extension for Swizzling

extension UIViewController {
    
    @objc func tk_viewDidAppear(_ animated: Bool) {
        // Call original implementation
        tk_viewDidAppear(animated)
        
        // Call our tracking handler
        if let autoTracker = TrackKit.shared.autoTracker,
           let tracker = autoTracker.viewTracker {
            tracker.handleViewDidAppear(self, animated: animated)
        }
    }
    
    @objc func tk_viewDidDisappear(_ animated: Bool) {
        // Call original implementation
        tk_viewDidDisappear(animated)
        
        // Call our tracking handler
        if let autoTracker = TrackKit.shared.autoTracker,
           let tracker = autoTracker.viewTracker {
            tracker.handleViewDidDisappear(self, animated: animated)
        }
    }
} 