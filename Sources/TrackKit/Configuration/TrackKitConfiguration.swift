import Foundation

/// Main configuration for TrackKit SDK
public struct TrackKitConfiguration {
    
    // MARK: - Basic Configuration
    public let apiKey: String
    public let baseURL: String
    public let apiVersion: String
    
    // MARK: - Endpoint Configuration
    public var endpoints: EndpointConfiguration
    
    // MARK: - Authentication
    public var authentication: AuthenticationMethod
    
    // MARK: - Tracking Configuration
    public var autoTrackingEnabled: Bool
    public var autoTrackViews: Bool
    public var autoTrackButtons: Bool
    public var autoTrackErrors: Bool
    
    // MARK: - Network Configuration
    public var batchSize: Int
    public var flushInterval: TimeInterval
    public var requestTimeout: TimeInterval
    public var retryPolicy: RetryPolicy
    
    // MARK: - Storage Configuration
    public var maxEventAge: TimeInterval
    public var maxStoredEvents: Int
    
    // MARK: - Debug Configuration
    public var enableDebugLogging: Bool
    
    // MARK: - Customization
    public var requestInterceptors: [RequestInterceptor]
    public var responseHandlers: [ResponseHandler]
    public var payloadFormatter: PayloadFormatter?
    
    // MARK: - Initialization
    public init(apiKey: String, baseURL: String, apiVersion: String = "v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiVersion = apiVersion
        
        // Default endpoint configuration
        self.endpoints = EndpointConfiguration.default
        
        // Default authentication
        self.authentication = .apiKey(APIKeyConfig(key: apiKey))
        
        // Default tracking settings
        self.autoTrackingEnabled = true
        self.autoTrackViews = true
        self.autoTrackButtons = true
        self.autoTrackErrors = true
        
        // Default network settings
        self.batchSize = 50
        self.flushInterval = 30.0
        self.requestTimeout = 30.0
        self.retryPolicy = .default
        
        // Default storage settings
        self.maxEventAge = 7 * 24 * 60 * 60 // 7 days
        self.maxStoredEvents = 1000
        
        // Default debug settings
        self.enableDebugLogging = false
        
        // Default customization
        self.requestInterceptors = []
        self.responseHandlers = []
        self.payloadFormatter = nil
    }
}

// MARK: - Endpoint Configuration
public struct EndpointConfiguration {
    public var events: EventEndpoints
    public var configuration: ConfigEndpoints
    public var health: String
    
    public struct EventEndpoints {
        public var single: String
        public var batch: String
        public var realtime: String
        
        public init(single: String = "/events", batch: String = "/events/batch", realtime: String = "/events/realtime") {
            self.single = single
            self.batch = batch
            self.realtime = realtime
        }
    }
    
    public struct ConfigEndpoints {
        public var fetch: String
        public var update: String
        
        public init(fetch: String = "/config", update: String = "/config/update") {
            self.fetch = fetch
            self.update = update
        }
    }
    
    public init(
        events: EventEndpoints = EventEndpoints(),
        configuration: ConfigEndpoints = ConfigEndpoints(),
        health: String = "/health"
    ) {
        self.events = events
        self.configuration = configuration
        self.health = health
    }
    
    public static let `default` = EndpointConfiguration()
    
    public static func custom(
        singleEvent: String = "/events",
        batchEvents: String = "/events/batch",
        realtimeEvents: String = "/events/realtime",
        configFetch: String = "/config",
        configUpdate: String = "/config/update",
        health: String = "/health"
    ) -> EndpointConfiguration {
        return EndpointConfiguration(
            events: EventEndpoints(single: singleEvent, batch: batchEvents, realtime: realtimeEvents),
            configuration: ConfigEndpoints(fetch: configFetch, update: configUpdate),
            health: health
        )
    }
}

// MARK: - Authentication Methods
public enum AuthenticationMethod {
    case none
    case apiKey(APIKeyConfig)
    case bearerToken(String)
    case oauth(OAuthConfig)
    case custom(CustomAuthConfig)
}

public struct APIKeyConfig {
    let key: String
    let headerName: String
    let prefix: String?
    
    public init(key: String, headerName: String = "Authorization", prefix: String? = "Bearer") {
        self.key = key
        self.headerName = headerName
        self.prefix = prefix
    }
}

public struct OAuthConfig {
    let clientId: String
    let clientSecret: String
    let tokenEndpoint: String
    let scopes: [String]
    
    public init(clientId: String, clientSecret: String, tokenEndpoint: String, scopes: [String] = []) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
    }
}

public struct CustomAuthConfig {
    let headers: [String: String]
    let queryParameters: [String: String]
    let bodyParameters: [String: String]
    
    public init(
        headers: [String: String] = [:],
        queryParameters: [String: String] = [:],
        bodyParameters: [String: String] = [:]
    ) {
        self.headers = headers
        self.queryParameters = queryParameters
        self.bodyParameters = bodyParameters
    }
}

// MARK: - Retry Policy
public struct RetryPolicy {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double
    let jitterRange: ClosedRange<Double>
    
    public init(
        maxRetries: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        backoffMultiplier: Double,
        jitterRange: ClosedRange<Double>
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.jitterRange = jitterRange
    }
    
    public static let `default` = RetryPolicy(
        maxRetries: 3,
        baseDelay: 1.0,
        maxDelay: 30.0,
        backoffMultiplier: 2.0,
        jitterRange: 0.8...1.2
    )
    
    public static let aggressive = RetryPolicy(
        maxRetries: 5,
        baseDelay: 0.5,
        maxDelay: 60.0,
        backoffMultiplier: 2.5,
        jitterRange: 0.5...1.5
    )
    
    public static let conservative = RetryPolicy(
        maxRetries: 2,
        baseDelay: 2.0,
        maxDelay: 20.0,
        backoffMultiplier: 1.5,
        jitterRange: 0.9...1.1
    )
}

// MARK: - Preset Configurations
public extension TrackKitConfiguration {
    
    /// Generic REST API configuration
    static func restAPI(
        apiKey: String,
        baseURL: String,
        authHeader: String = "Authorization"
    ) -> TrackKitConfiguration {
        var config = TrackKitConfiguration(apiKey: apiKey, baseURL: baseURL)
        config.authentication = .apiKey(APIKeyConfig(key: apiKey, headerName: authHeader))
        return config
    }
    
    /// Webhook configuration
    static func webhook(url: String, headers: [String: String] = [:]) -> TrackKitConfiguration {
        var config = TrackKitConfiguration(apiKey: "", baseURL: url)
        config.endpoints = .custom(singleEvent: "", batchEvents: "")
        config.authentication = .custom(CustomAuthConfig(headers: headers))
        return config
    }
} 