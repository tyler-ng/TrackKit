import Foundation
import UIKit

/// Tracks button taps and UI interactions automatically
internal class ButtonTracker {
    
    // MARK: - Properties
    private let eventTracker: EventTracker
    private var isTracking = false
    private var eventsTrackedCount = 0
    
    private var originalSendActionMethod: Method?
    
    // MARK: - Initialization
    init(eventTracker: EventTracker) {
        self.eventTracker = eventTracker
    }
    
    deinit {
        stopTracking()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking button interactions
    func startTracking() {
        guard !isTracking else { return }
        
        isTracking = true
        swizzleSendAction()
        
        TrackKitLogger.debug("Button tracking started")
    }
    
    /// Stop tracking button interactions
    func stopTracking() {
        guard isTracking else { return }
        
        isTracking = false
        // Note: We don't unswizzle methods to avoid potential crashes
        
        TrackKitLogger.debug("Button tracking stopped")
    }
    
    /// Get number of events tracked
    var eventsTracked: Int {
        return eventsTrackedCount
    }
    
    // MARK: - Private Methods
    
    private func swizzleSendAction() {
        let originalSelector = #selector(UIApplication.sendAction(_:to:from:for:))
        let swizzledSelector = #selector(UIApplication.tk_sendAction(_:to:from:for:))
        
        guard let originalMethod = class_getInstanceMethod(UIApplication.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIApplication.self, swizzledSelector) else {
            TrackKitLogger.error("Failed to get methods for sendAction swizzling")
            return
        }
        
        originalSendActionMethod = originalMethod
        
        let didAddMethod = class_addMethod(
            UIApplication.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        
        if didAddMethod {
            class_replaceMethod(
                UIApplication.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
    
    @objc private func handleSendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) {
        guard isTracking else { return }
        
        // Track different types of UI interactions
        if let button = sender as? UIButton {
            trackButtonTap(button, action: action, event: event)
        } else if let segmentedControl = sender as? UISegmentedControl {
            trackSegmentedControlTap(segmentedControl, action: action, event: event)
        } else if let stepper = sender as? UIStepper {
            trackStepperTap(stepper, action: action, event: event)
        } else if let slider = sender as? UISlider {
            trackSliderChange(slider, action: action, event: event)
        } else if let control = sender as? UIControl {
            trackGenericControlTap(control, action: action, event: event)
        }
    }
    
    private func trackButtonTap(_ button: UIButton, action: Selector, event: UIEvent?) {
        let buttonName = getButtonIdentifier(button)
        var properties = extractButtonProperties(button)
        properties["action"] = NSStringFromSelector(action)
        properties["button_type"] = "UIButton"
        
        let buttonEvent = ButtonEvent(
            buttonName: buttonName,
            properties: properties,
            buttonType: "UIButton"
        )
        
        eventTracker.track(event: buttonEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked button tap: \(buttonName)")
    }
    
    private func trackSegmentedControlTap(_ segmentedControl: UISegmentedControl, action: Selector, event: UIEvent?) {
        let controlName = getControlIdentifier(segmentedControl)
        var properties = extractControlProperties(segmentedControl)
        properties["action"] = NSStringFromSelector(action)
        properties["button_type"] = "UISegmentedControl"
        properties["selected_segment"] = segmentedControl.selectedSegmentIndex
        properties["number_of_segments"] = segmentedControl.numberOfSegments
        
        if segmentedControl.selectedSegmentIndex >= 0 && segmentedControl.selectedSegmentIndex < segmentedControl.numberOfSegments {
            properties["selected_segment_title"] = segmentedControl.titleForSegment(at: segmentedControl.selectedSegmentIndex)
        }
        
        let buttonEvent = ButtonEvent(
            buttonName: controlName,
            properties: properties,
            buttonType: "UISegmentedControl"
        )
        
        eventTracker.track(event: buttonEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked segmented control tap: \(controlName)")
    }
    
    private func trackStepperTap(_ stepper: UIStepper, action: Selector, event: UIEvent?) {
        let stepperName = getControlIdentifier(stepper)
        var properties = extractControlProperties(stepper)
        properties["action"] = NSStringFromSelector(action)
        properties["button_type"] = "UIStepper"
        properties["value"] = stepper.value
        properties["minimum_value"] = stepper.minimumValue
        properties["maximum_value"] = stepper.maximumValue
        properties["step_value"] = stepper.stepValue
        
        let buttonEvent = ButtonEvent(
            buttonName: stepperName,
            properties: properties,
            buttonType: "UIStepper"
        )
        
        eventTracker.track(event: buttonEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked stepper tap: \(stepperName)")
    }
    
    private func trackSliderChange(_ slider: UISlider, action: Selector, event: UIEvent?) {
        let sliderName = getControlIdentifier(slider)
        var properties = extractControlProperties(slider)
        properties["action"] = NSStringFromSelector(action)
        properties["button_type"] = "UISlider"
        properties["value"] = slider.value
        properties["minimum_value"] = slider.minimumValue
        properties["maximum_value"] = slider.maximumValue
        
        let buttonEvent = ButtonEvent(
            buttonName: sliderName,
            properties: properties,
            buttonType: "UISlider"
        )
        
        eventTracker.track(event: buttonEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked slider change: \(sliderName)")
    }
    
    private func trackGenericControlTap(_ control: UIControl, action: Selector, event: UIEvent?) {
        let controlName = getControlIdentifier(control)
        var properties = extractControlProperties(control)
        properties["action"] = NSStringFromSelector(action)
        properties["button_type"] = String(describing: type(of: control))
        
        let buttonEvent = ButtonEvent(
            buttonName: controlName,
            properties: properties,
            buttonType: String(describing: type(of: control))
        )
        
        eventTracker.track(event: buttonEvent)
        eventsTrackedCount += 1
        
        TrackKitLogger.debug("Tracked control interaction: \(controlName)")
    }
    
    private func getButtonIdentifier(_ button: UIButton) -> String {
        // Try to get a meaningful identifier for the button
        if let title = button.title(for: .normal), !title.isEmpty {
            return title
        }
        
        if let accessibilityLabel = button.accessibilityLabel, !accessibilityLabel.isEmpty {
            return accessibilityLabel
        }
        
        if let accessibilityIdentifier = button.accessibilityIdentifier, !accessibilityIdentifier.isEmpty {
            return accessibilityIdentifier
        }
        
        if button.tag != 0 {
            return "Button_\(button.tag)"
        }
        
        // Fallback to memory address
        return "Button_\(Unmanaged.passUnretained(button).toOpaque())"
    }
    
    private func getControlIdentifier(_ control: UIControl) -> String {
        if let accessibilityLabel = control.accessibilityLabel, !accessibilityLabel.isEmpty {
            return accessibilityLabel
        }
        
        if let accessibilityIdentifier = control.accessibilityIdentifier, !accessibilityIdentifier.isEmpty {
            return accessibilityIdentifier
        }
        
        if control.tag != 0 {
            return "\(String(describing: type(of: control)))_\(control.tag)"
        }
        
        // Fallback to memory address
        return "\(String(describing: type(of: control)))_\(Unmanaged.passUnretained(control).toOpaque())"
    }
    
    private func extractButtonProperties(_ button: UIButton) -> [String: Any] {
        var properties = extractControlProperties(button)
        
        // Button-specific properties
        properties["current_title"] = button.title(for: .normal)
        properties["current_attributed_title"] = button.attributedTitle(for: .normal)?.string
        properties["button_type"] = button.buttonType.rawValue
        properties["content_horizontal_alignment"] = button.contentHorizontalAlignment.rawValue
        properties["content_vertical_alignment"] = button.contentVerticalAlignment.rawValue
        
        // Image properties
        if let image = button.image(for: .normal) {
            properties["has_image"] = true
            properties["image_size"] = NSStringFromCGSize(image.size)
        } else {
            properties["has_image"] = false
        }
        
        return properties
    }
    
    private func extractControlProperties(_ control: UIControl) -> [String: Any] {
        var properties: [String: Any] = [:]
        
        // Basic properties
        properties["control_class"] = String(describing: type(of: control))
        properties["enabled"] = control.isEnabled
        properties["selected"] = control.isSelected
        properties["highlighted"] = control.isHighlighted
        properties["tag"] = control.tag
        
        // Accessibility properties
        properties["accessibility_label"] = control.accessibilityLabel
        properties["accessibility_identifier"] = control.accessibilityIdentifier
        properties["accessibility_hint"] = control.accessibilityHint
        
        // Frame properties
        properties["frame"] = NSStringFromCGRect(control.frame)
        properties["bounds"] = NSStringFromCGRect(control.bounds)
        
        // Superview information
        if let superview = control.superview {
            properties["superview_class"] = String(describing: type(of: superview))
        }
        
        // Find containing view controller
        if let viewController = control.findViewController() {
            properties["containing_view_controller"] = String(describing: type(of: viewController))
        }
        
        return properties
    }
}

// MARK: - UIApplication Extension for Swizzling

extension UIApplication {
    
    @objc func tk_sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
        // Call our tracking handler first
        if let autoTracker = TrackKit.shared.autoTracker,
           let tracker = autoTracker.buttonTracker {
            tracker.handleSendAction(action, to: target, from: sender, for: event)
        }
        
        // Call original implementation
        return tk_sendAction(action, to: target, from: sender, for: event)
    }
}

// MARK: - UIView Extension for Finding View Controller

extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
} 