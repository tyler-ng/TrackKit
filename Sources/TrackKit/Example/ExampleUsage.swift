import Foundation
import UIKit

/*
 Example usage of TrackKit SDK for iOS
 
 This file demonstrates how to integrate and use TrackKit in your iOS application.
 It's provided as documentation and should not be included in production builds.
 */

class ExampleViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTrackKit()
        demonstrateTrackingUsage()
    }
    
    // MARK: - Setup
    
    private func setupTrackKit() {
        // Basic configuration
        TrackKit.configure(apiKey: "your-api-key", endpoint: "https://your-api.com")
        
        // Or with custom endpoints
        TrackKit.configureWithCustomEndpoints(
            apiKey: "your-api-key",
            baseURL: "https://your-api.com",
            singleEventEndpoint: "/track",
            batchEndpoint: "/batch"
        )
        
        // Enable debug logging
        TrackKit.enableDebugLogging(true)
        
        // Set user information
        TrackKit.setUserId("user123")
        TrackKit.setUserProperties([
            "name": "John Doe",
            "email": "john@example.com",
            "plan": "premium"
        ])
        
        // Configure batching
        TrackKit.setBatchSize(10)
        TrackKit.setFlushInterval(30.0) // 30 seconds
    }
    
    // MARK: - Tracking Examples
    
    private func demonstrateTrackingUsage() {
        // Track custom events
        TrackKit.track(event: "app_launched")
        
        TrackKit.track(event: "user_action", properties: [
            "action_type": "button_tap",
            "screen": "home",
            "timestamp": Date().timeIntervalSince1970
        ])
        
        // Track views manually
        TrackKit.trackView("HomeScreen", properties: [
            "user_type": "premium",
            "session_duration": 150.0
        ])
        
        // Track button interactions manually
        TrackKit.trackButton("login_button", properties: [
            "button_location": "navigation_bar",
            "user_logged_in": false
        ])
        
        // Track errors
        let error = NSError(domain: "com.example.app", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "User not found"
        ])
        TrackKit.trackError(error, properties: [
            "error_context": "user_login",
            "retry_count": 3
        ])
    }
    
    // MARK: - Auto-Tracking Examples
    
    private func setupAutoTracking() {
        // Enable auto-tracking for automatic view and button tracking
        TrackKit.enableAutoTracking(true)
        
        // Note: Auto-tracking will automatically capture:
        // - View controller appearances/disappearances
        // - Button taps and UI interactions
        // - Uncaught exceptions and crashes
    }
    
    // MARK: - Advanced Usage
    
    private func advancedUsage() {
        // Manual flush (force send all pending events)
        TrackKit.flush()
        
        // Reset SDK state
        TrackKit.reset()
        
        // Check configuration status
        if TrackKit.isConfigured {
            print("TrackKit is ready to track events")
        }
        
        // Get SDK version
        print("Using TrackKit version: \(TrackKit.version)")
    }
    
    // MARK: - Button Actions (for testing)
    
    @IBAction func loginButtonTapped(_ sender: UIButton) {
        // This will be automatically tracked if auto-tracking is enabled
        // Or you can manually track it:
        TrackKit.trackButton("login_button", properties: [
            "source": "manual_tracking"
        ])
        
        // Simulate user login
        simulateUserLogin()
    }
    
    @IBAction func purchaseButtonTapped(_ sender: UIButton) {
        TrackKit.track(event: "purchase_initiated", properties: [
            "product_id": "premium_plan",
            "price": 9.99,
            "currency": "USD"
        ])
    }
    
    private func simulateUserLogin() {
        // Simulate API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if Bool.random() {
                // Success
                TrackKit.track(event: "login_success", properties: [
                    "method": "email"
                ])
                TrackKit.setUserId("user123")
            } else {
                // Error
                let error = NSError(domain: "LoginError", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid credentials"
                ])
                TrackKit.trackError(error, properties: [
                    "login_method": "email"
                ])
            }
        }
    }
}

// MARK: - AppDelegate Integration

extension UIApplicationDelegate {
    
    func setupTrackKitInAppDelegate() {
        // Configure TrackKit early in app lifecycle
        TrackKit.configure(apiKey: "your-api-key", endpoint: "https://your-api.com")
        
        // Enable auto-tracking
        TrackKit.enableAutoTracking(true)
        
        // Track app launch
        TrackKit.track(event: "app_launched", properties: [
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        ])
    }
}

// MARK: - Example Configuration for Different Environments

struct TrackKitConfig {
    
    static func configureForDevelopment() {
        TrackKit.configure(apiKey: "dev-api-key", endpoint: "https://dev-api.example.com")
        TrackKit.enableDebugLogging(true)
        TrackKit.setBatchSize(1) // Send events immediately in development
    }
    
    static func configureForProduction() {
        TrackKit.configure(apiKey: "prod-api-key", endpoint: "https://api.example.com")
        TrackKit.enableDebugLogging(false)
        TrackKit.setBatchSize(20) // Batch events in production
        TrackKit.setFlushInterval(60.0) // Flush every minute
    }
    
    static func configureForTesting() {
        // Don't send any real events during testing
        // You might want to use a test endpoint or disable tracking entirely
        TrackKit.configure(apiKey: "test-api-key", endpoint: "https://test-api.example.com")
        TrackKit.enableDebugLogging(true)
    }
} 