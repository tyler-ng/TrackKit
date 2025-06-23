import Foundation

// MARK: - Request/Response Interceptors

/// Protocol for intercepting and modifying requests before they are sent
public protocol RequestInterceptor {
    func intercept(request: URLRequest, context: RequestContext) -> URLRequest
}

/// Protocol for handling responses from the server
public protocol ResponseHandler {
    func handleSuccess(data: Data?, response: URLResponse, context: RequestContext)
    func handleError(error: Error, response: URLResponse?, context: RequestContext) -> Bool // return true if handled
}

/// Context information for request/response interceptors
public struct RequestContext {
    public let eventType: EventType
    public let deliveryType: DeliveryType
    public let attemptNumber: Int
    public let metadata: [String: Any]
    
    public init(eventType: EventType, deliveryType: DeliveryType, attemptNumber: Int = 1, metadata: [String: Any] = [:]) {
        self.eventType = eventType
        self.deliveryType = deliveryType
        self.attemptNumber = attemptNumber
        self.metadata = metadata
    }
}

/// Types of event delivery
public enum DeliveryType {
    case single
    case batch
    case realtime
}

// MARK: - Payload Formatting

/// Protocol for custom payload formatting
public protocol PayloadFormatter {
    func formatSingleEvent(_ event: Event) -> [String: Any]
    func formatBatchEvents(_ events: [Event]) -> [String: Any]
}

/// Default payload formatter
public struct DefaultPayloadFormatter: PayloadFormatter {
    public init() {}
    
    public func formatSingleEvent(_ event: Event) -> [String: Any] {
        return event.toDictionary()
    }
    
    public func formatBatchEvents(_ events: [Event]) -> [String: Any] {
        return [
            "events": events.map { $0.toDictionary() },
            "batch_size": events.count,
            "batch_timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }
}

// MARK: - Event Delivery Delegate

/// Delegate protocol for event delivery notifications
public protocol EventDeliveryDelegate: AnyObject {
    func willSendEvent(_ event: Event, endpoint: String)
    func didSendEvent(_ event: Event, success: Bool, error: Error?)
    func willSendBatch(_ events: [Event], endpoint: String)
    func didSendBatch(_ events: [Event], success: Bool, error: Error?)
    func deliveryFailed(_ events: [Event], error: Error, willRetry: Bool)
}

// MARK: - Network Error Types

/// Network-related errors
public enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noInternetConnection
    case timeout
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case serverError(Int, String)
    case rateLimited(retryAfter: TimeInterval?)
    case payloadTooLarge
    case invalidResponse
    case serializationError(Error)
    case custom(String, Int?)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noInternetConnection:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .unauthorized(let message):
            return "Unauthorized: \(message)"
        case .forbidden(let message):
            return "Forbidden: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .rateLimited(let retryAfter):
            let retryMessage = retryAfter.map { " (retry after \($0)s)" } ?? ""
            return "Rate limited\(retryMessage)"
        case .payloadTooLarge:
            return "Payload too large"
        case .invalidResponse:
            return "Invalid response"
        case .serializationError(let error):
            return "Serialization error: \(error.localizedDescription)"
        case .custom(let message, let code):
            let codeMessage = code.map { " (\($0))" } ?? ""
            return "Error\(codeMessage): \(message)"
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .timeout, .serverError, .rateLimited, .noInternetConnection:
            return true
        case .unauthorized, .forbidden, .notFound, .payloadTooLarge, .invalidURL, .invalidResponse:
            return false
        case .serializationError, .custom:
            return false
        }
    }
}

// MARK: - Delivery Results

/// Result of single event delivery
public struct EventDeliveryResult {
    public let success: Bool
    public let error: NetworkError?
    public let responseTime: TimeInterval
    public let retryCount: Int
    public let eventId: String
    public let statusCode: Int?
    
    public init(success: Bool, error: NetworkError? = nil, responseTime: TimeInterval, retryCount: Int, eventId: String, statusCode: Int? = nil) {
        self.success = success
        self.error = error
        self.responseTime = responseTime
        self.retryCount = retryCount
        self.eventId = eventId
        self.statusCode = statusCode
    }
}

/// Result of batch delivery
public struct BatchDeliveryResult {
    public let totalEvents: Int
    public let successCount: Int
    public let failedEvents: [String] // Event IDs
    public let errors: [NetworkError]
    public let responseTime: TimeInterval
    public let statusCode: Int?
    
    public init(totalEvents: Int, successCount: Int, failedEvents: [String], errors: [NetworkError], responseTime: TimeInterval, statusCode: Int? = nil) {
        self.totalEvents = totalEvents
        self.successCount = successCount
        self.failedEvents = failedEvents
        self.errors = errors
        self.responseTime = responseTime
        self.statusCode = statusCode
    }
    
    public var successRate: Double {
        guard totalEvents > 0 else { return 0 }
        return Double(successCount) / Double(totalEvents)
    }
}

// MARK: - HTTP Methods and Headers

/// HTTP methods used by the SDK
public enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}

/// Standard HTTP headers
public struct HTTPHeaders {
    public static let contentType = "Content-Type"
    public static let authorization = "Authorization"
    public static let userAgent = "User-Agent"
    public static let accept = "Accept"
    public static let acceptEncoding = "Accept-Encoding"
    public static let contentEncoding = "Content-Encoding"
    public static let retryAfter = "Retry-After"
}

/// Content types
public struct ContentType {
    public static let json = "application/json"
    public static let formURLEncoded = "application/x-www-form-urlencoded"
    public static let multipartFormData = "multipart/form-data"
}

// MARK: - Request Configuration

/// Configuration for individual requests
public struct RequestConfiguration {
    public let timeout: TimeInterval
    public let retryPolicy: RetryPolicy
    public let priority: EventPriority
    public let headers: [String: String]
    public let compress: Bool
    
    public init(
        timeout: TimeInterval = 30.0,
        retryPolicy: RetryPolicy = .default,
        priority: EventPriority = .normal,
        headers: [String: String] = [:],
        compress: Bool = false
    ) {
        self.timeout = timeout
        self.retryPolicy = retryPolicy
        self.priority = priority
        self.headers = headers
        self.compress = compress
    }
    
    public static let `default` = RequestConfiguration()
    
    public static let realtime = RequestConfiguration(
        timeout: 10.0,
        retryPolicy: .aggressive,
        priority: .critical
    )
    
    public static let batch = RequestConfiguration(
        timeout: 60.0,
        retryPolicy: .conservative,
        priority: .normal,
        compress: true
    )
} 