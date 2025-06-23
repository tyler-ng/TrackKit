# TrackKit iOS SDK

A powerful, lightweight iOS tracking SDK with automatic event tracking, minimal performance impact, and flexible backend integration.

## Features

- 🎯 **Automatic Event Tracking**: UIViewController views, button taps, and crashes
- 📱 **iOS Optimized**: Built specifically for iOS 12+ using UIKit
- ⚡ **High Performance**: Minimal impact on app performance with background processing
- 🔄 **Intelligent Batching**: Efficient event batching with configurable batch sizes
- 🛡️ **Error Handling**: Automatic crash detection and error tracking
- 🌐 **Flexible API**: Support for multiple backend configurations
- 📊 **Rich Context**: Automatic device, app, and session information
- 🔧 **Thread Safe**: All operations are thread-safe and non-blocking

## Installation

### Swift Package Manager

Add TrackKit to your project using Xcode:

1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/tyler-ng/TrackKit`
3. Select the version and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tyler-ng/TrackKit", from: "1.0.0")
]
```

## Quick Start

### 1. Configure TrackKit

In your `AppDelegate` or `SceneDelegate`:

```swift
import TrackKit

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Basic configuration
    TrackKit.configure(apiKey: "your-api-key", endpoint: "https://your-api.com")
    
    // Enable auto-tracking
    TrackKit.enableAutoTracking(true)
    
    return true
}
```

### 2. Track Events

```swift
// Track custom events
TrackKit.track(event: "user_signup", properties: [
    "method": "email",
    "plan": "premium"
])

// Track views
TrackKit.trackView("HomeScreen")

// Track button interactions
TrackKit.trackButton("purchase_button")

// Track errors
TrackKit.trackError(error)
```

### 3. Set User Information

```swift
TrackKit.setUserId("user123")
TrackKit.setUserProperties([
    "name": "John Doe",
    "email": "john@example.com",
    "plan": "premium"
])
```

## Advanced Configuration

### Custom Endpoints

```swift
TrackKit.configureWithCustomEndpoints(
    apiKey: "your-api-key",
    baseURL: "https://your-api.com",
    singleEventEndpoint: "/track",
    batchEndpoint: "/batch"
)
```

### Complete Configuration

```swift
var config = TrackKitConfiguration(apiKey: "your-api-key", baseURL: "https://your-api.com")

// Endpoints
config.endpoints = .custom(singleEvent: "/events", batchEvents: "/events/batch")

// Authentication
config.authentication = .bearerToken("your-bearer-token")

// Batching
config.batchSize = 20
config.flushInterval = 60.0
config.maxRetries = 3

// Auto-tracking
config.autoTrackingEnabled = true

// Performance
config.maxQueueSize = 1000

TrackKit.configure(with: config)
```

## Auto-Tracking

TrackKit automatically tracks:

### View Controllers
- View appearances and disappearances
- Navigation stack depth
- Modal presentations
- View duration

### UI Interactions
- Button taps
- Segmented control selections
- Stepper interactions
- Slider changes
- Generic UIControl events

### Error Tracking
- Uncaught exceptions
- Signal crashes (SIGSEGV, SIGABRT, etc.)
- Network errors
- Custom application errors

### Configuring Auto-Tracking

```swift
// Enable/disable auto-tracking
TrackKit.enableAutoTracking(true)

// Ignore specific view controllers (if using auto-tracking)
let autoTracker = TrackKit.shared.autoTracker
autoTracker?.ignoreViewControllers([UINavigationController.self])
autoTracker?.ignoreViewControllerNames(["PrivacyViewController"])
```

## Event Types

### Custom Events
```swift
TrackKit.track(event: "purchase_completed", properties: [
    "product_id": "premium_plan",
    "price": 9.99,
    "currency": "USD"
])
```

### View Events
```swift
TrackKit.trackView("ProductDetailScreen", properties: [
    "product_id": "123",
    "category": "electronics"
])
```

### Button Events
```swift
TrackKit.trackButton("add_to_cart", properties: [
    "product_id": "123",
    "source": "product_page"
])
```

### Error Events
```swift
TrackKit.trackError(error, properties: [
    "context": "user_login",
    "retry_count": 3
])
```

## Performance Features

### Intelligent Batching
- Events are batched for efficient network usage
- Critical events (errors) are sent immediately
- Configurable batch sizes and intervals

### Background Processing
- All tracking operations happen on background queues
- Non-blocking main thread
- Automatic queue management

### Memory Management
- Automatic cleanup of old events
- Configurable maximum queue size
- Memory-efficient event storage

## API Integration

### Supported Authentication Methods
- API Key
- Bearer Token
- OAuth
- Custom headers

### Request/Response Interceptors
```swift
config.requestInterceptor = { request in
    // Modify request before sending
    request.addValue("custom-value", forHTTPHeaderField: "Custom-Header")
    return request
}

config.responseInterceptor = { data, response in
    // Process response data
    print("Response received: \(response.statusCode)")
}
```

### Backend Integration Examples

#### Custom REST API
```swift
var config = TrackKitConfiguration(apiKey: "your-api-key", baseURL: "https://your-api.com")
config.endpoints = .custom(singleEvent: "/track", batchEvents: "/batch")
config.authentication = .apiKey(APIKeyConfig(key: "your-api-key"))
```

#### Webhook Integration
```swift
var config = TrackKitConfiguration.webhook(
    url: "https://your-webhook.com",
    headers: ["Custom-Header": "value"]
)
```

#### Generic REST API
```swift
var config = TrackKitConfiguration.restAPI(
    apiKey: "your-api-key",
    baseURL: "https://your-api.com",
    authHeader: "Authorization"
)
```

## Debugging

### Enable Debug Logging
```swift
TrackKit.enableDebugLogging(true)
```

### Check SDK Status
```swift
if TrackKit.isConfigured {
    print("TrackKit is ready")
}

print("SDK Version: \(TrackKit.version)")
```

### Manual Operations
```swift
// Force send all pending events
TrackKit.flush()

// Reset SDK state
TrackKit.reset()

// Configure batching
TrackKit.setBatchSize(10)
TrackKit.setFlushInterval(30.0)
```

## Thread Safety

TrackKit is fully thread-safe:
- All public methods can be called from any thread
- Internal operations are synchronized
- Background processing prevents main thread blocking

## Privacy

TrackKit automatically collects:
- Device information (model, OS version, etc.)
- App information (version, bundle ID, etc.)
- Session information (start time, duration, etc.)
- View controller names and properties
- User interactions with UI elements

All data collection can be configured or disabled as needed.

## Requirements

- iOS 12.0+
- Xcode 12.0+
- Swift 5.0+

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

TrackKit is available under the MIT license. See the LICENSE file for more info.

## Support

- 📧 Email: support@trackkit.dev
- 🐛 Issues: [GitHub Issues](https://github.com/tyler-ng/TrackKit/issues)
- 📖 Documentation: [Full Documentation](https://docs.trackkit.dev)

---

Made with ❤️ for iOS developers 