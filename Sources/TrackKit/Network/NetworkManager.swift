import Foundation

/// Network manager for sending events to the backend
public class NetworkManager {
    
    // MARK: - Properties
    private let configuration: TrackKitConfiguration
    private let session: URLSession
    private let payloadFormatter: PayloadFormatter
    weak var delegate: NetworkManagerDelegate?
    
    private let queue = DispatchQueue(label: "com.trackkit.network", qos: .utility)
    
    // MARK: - Initialization
    public init(configuration: TrackKitConfiguration) {
        self.configuration = configuration
        self.payloadFormatter = configuration.payloadFormatter ?? DefaultPayloadFormatter()
        
        // Configure URLSession
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.requestTimeout * 2
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: sessionConfig)
    }
    
    // MARK: - Public Methods
    
    /// Send a single event
    /// - Parameters:
    ///   - event: Event to send
    ///   - context: Request context
    ///   - completion: Completion handler
    public func sendSingleEvent(
        _ event: TrackingEvent,
        context: RequestContext,
        completion: @escaping (EventDeliveryResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let startTime = Date()
            let endpoint = self.buildEndpoint(for: .single)
            
            DispatchQueue.main.async {
                self.delegate?.networkManager(self, didCompleteRequest: context, result: EventDeliveryResult(
                    success: false,
                    error: .invalidURL,
                    responseTime: 0,
                    retryCount: 0,
                    eventId: event.id
                ))
            }
            
            guard let request = self.buildRequest(
                endpoint: endpoint,
                payload: self.payloadFormatter.formatSingleEvent(event),
                context: context
            ) else {
                let result = EventDeliveryResult(
                    success: false,
                    error: .invalidURL,
                    responseTime: 0,
                    retryCount: context.attemptNumber,
                    eventId: event.id
                )
                DispatchQueue.main.async { completion(result) }
                return
            }
            
            TrackKitLogger.logNetworkRequest(
                url: request.url?.absoluteString ?? "",
                method: request.httpMethod ?? "",
                headers: request.allHTTPHeaderFields
            )
            
            self.performRequest(request, event: event, context: context, startTime: startTime, completion: completion)
        }
    }
    
    /// Send a batch of events
    /// - Parameters:
    ///   - events: Events to send
    ///   - context: Request context
    ///   - completion: Completion handler
    public func sendBatch(
        _ events: [TrackingEvent],
        context: RequestContext,
        completion: @escaping (BatchDeliveryResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let startTime = Date()
            let endpoint = self.buildEndpoint(for: .batch)
            
            guard let request = self.buildRequest(
                endpoint: endpoint,
                payload: self.payloadFormatter.formatBatchEvents(events),
                context: context
            ) else {
                let result = BatchDeliveryResult(
                    totalEvents: events.count,
                    successCount: 0,
                    failedEvents: events.map { $0.id },
                    errors: [.invalidURL],
                    responseTime: 0
                )
                DispatchQueue.main.async { completion(result) }
                return
            }
            
            TrackKitLogger.logNetworkRequest(
                url: request.url?.absoluteString ?? "",
                method: request.httpMethod ?? "",
                headers: request.allHTTPHeaderFields
            )
            
            self.performBatchRequest(request, events: events, context: context, startTime: startTime, completion: completion)
        }
    }
    
    // MARK: - Private Methods
    
    private func buildEndpoint(for deliveryType: DeliveryType) -> String {
        let baseURL = configuration.baseURL
        
        switch deliveryType {
        case .single:
            return "\(baseURL)\(configuration.endpoints.events.single)"
        case .batch:
            return "\(baseURL)\(configuration.endpoints.events.batch)"
        case .realtime:
            return "\(baseURL)\(configuration.endpoints.events.realtime)"
        }
    }
    
    private func buildRequest(
        endpoint: String,
        payload: [String: Any],
        context: RequestContext
    ) -> URLRequest? {
        guard let url = URL(string: endpoint) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.POST.rawValue
        request.setValue(ContentType.json, forHTTPHeaderField: HTTPHeaders.contentType)
        request.setValue("TrackKit/1.0.0", forHTTPHeaderField: HTTPHeaders.userAgent)
        
        // Apply authentication
        applyAuthentication(to: &request)
        
        // Add custom headers
        for interceptor in configuration.requestInterceptors {
            request = interceptor.intercept(request: request, context: context)
        }
        
        // Serialize payload
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            TrackKitLogger.error("Failed to serialize payload: \(error)")
            return nil
        }
        
        return request
    }
    
    private func applyAuthentication(to request: inout URLRequest) {
        switch configuration.authentication {
        case .none:
            break
        case .apiKey(let config):
            let value = config.prefix.map { "\($0) \(config.key)" } ?? config.key
            request.setValue(value, forHTTPHeaderField: config.headerName)
        case .bearerToken(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: HTTPHeaders.authorization)
        case .oauth(let config):
            // OAuth implementation would go here
            // For now, just use client credentials
            request.setValue("Bearer \(config.clientId)", forHTTPHeaderField: HTTPHeaders.authorization)
        case .custom(let config):
            config.headers.forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
    }
    
    private func performRequest(
        _ request: URLRequest,
        event: TrackingEvent,
        context: RequestContext,
        startTime: Date,
        completion: @escaping (EventDeliveryResult) -> Void
    ) {
        session.dataTask(with: request) { [weak self] data, response, error in
            let responseTime = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
            
            guard let self = self else { return }
            
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode
            
            TrackKitLogger.logNetworkResponse(
                url: request.url?.absoluteString ?? "",
                statusCode: statusCode ?? 0,
                responseTime: responseTime
            )
            
            let result: EventDeliveryResult
            
            if let error = error {
                result = EventDeliveryResult(
                    success: false,
                    error: self.mapError(error, statusCode: statusCode),
                    responseTime: responseTime,
                    retryCount: context.attemptNumber,
                    eventId: event.id,
                    statusCode: statusCode
                )
            } else if let statusCode = statusCode, self.isSuccessStatusCode(statusCode) {
                result = EventDeliveryResult(
                    success: true,
                    error: nil,
                    responseTime: responseTime,
                    retryCount: context.attemptNumber,
                    eventId: event.id,
                    statusCode: statusCode
                )
            } else {
                result = EventDeliveryResult(
                    success: false,
                    error: self.mapStatusCodeToError(statusCode ?? 0),
                    responseTime: responseTime,
                    retryCount: context.attemptNumber,
                    eventId: event.id,
                    statusCode: statusCode
                )
            }
            
            // Handle response with custom handlers
            for handler in self.configuration.responseHandlers {
                if result.success {
                    handler.handleSuccess(data: data, response: response!, context: context)
                } else if let error = result.error {
                    _ = handler.handleError(error: error, response: response, context: context)
                }
            }
            
            DispatchQueue.main.async {
                completion(result)
                self.delegate?.networkManager(self, didCompleteRequest: context, result: result)
            }
        }.resume()
    }
    
    private func performBatchRequest(
        _ request: URLRequest,
        events: [TrackingEvent],
        context: RequestContext,
        startTime: Date,
        completion: @escaping (BatchDeliveryResult) -> Void
    ) {
        session.dataTask(with: request) { [weak self] data, response, error in
            let responseTime = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
            
            guard let self = self else { return }
            
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode
            
            TrackKitLogger.logNetworkResponse(
                url: request.url?.absoluteString ?? "",
                statusCode: statusCode ?? 0,
                responseTime: responseTime
            )
            
            let result: BatchDeliveryResult
            
            if let error = error {
                result = BatchDeliveryResult(
                    totalEvents: events.count,
                    successCount: 0,
                    failedEvents: events.map { $0.id },
                    errors: [self.mapError(error, statusCode: statusCode)],
                    responseTime: responseTime,
                    statusCode: statusCode
                )
            } else if let statusCode = statusCode, self.isSuccessStatusCode(statusCode) {
                result = BatchDeliveryResult(
                    totalEvents: events.count,
                    successCount: events.count,
                    failedEvents: [],
                    errors: [],
                    responseTime: responseTime,
                    statusCode: statusCode
                )
            } else {
                result = BatchDeliveryResult(
                    totalEvents: events.count,
                    successCount: 0,
                    failedEvents: events.map { $0.id },
                    errors: [self.mapStatusCodeToError(statusCode ?? 0)],
                    responseTime: responseTime,
                    statusCode: statusCode
                )
            }
            
            // Handle response with custom handlers
            for handler in self.configuration.responseHandlers {
                if result.successCount == result.totalEvents {
                    handler.handleSuccess(data: data, response: response!, context: context)
                } else if let error = result.errors.first {
                    _ = handler.handleError(error: error, response: response, context: context)
                }
            }
            
            DispatchQueue.main.async {
                completion(result)
                self.delegate?.networkManager(self, didCompleteBatch: context, result: result)
            }
        }.resume()
    }
    
    private func isSuccessStatusCode(_ statusCode: Int) -> Bool {
        return 200...299 ~= statusCode
    }
    
    private func mapError(_ error: Error, statusCode: Int?) -> NetworkError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .noInternetConnection
            case .timedOut:
                return .timeout
            case .badURL:
                return .invalidURL
            default:
                return .custom(urlError.localizedDescription, statusCode)
            }
        }
        
        return .custom(error.localizedDescription, statusCode)
    }
    
    private func mapStatusCodeToError(_ statusCode: Int) -> NetworkError {
        switch statusCode {
        case 401:
            return .unauthorized("Authentication failed")
        case 403:
            return .forbidden("Access forbidden")
        case 404:
            return .notFound("Endpoint not found")
        case 413:
            return .payloadTooLarge
        case 429:
            return .rateLimited(retryAfter: nil)
        case 500...599:
            return .serverError(statusCode, "Server error")
        default:
            return .custom("HTTP \(statusCode)", statusCode)
        }
    }
} 