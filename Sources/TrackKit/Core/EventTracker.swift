import Foundation

/// Main event tracking and delivery coordinator
public class EventTracker {
    
    // MARK: - Properties
    private let configuration: TrackKitConfiguration
    private let sessionManager: SessionManager
    private let eventQueue: EventQueue
    private let networkManager: NetworkManager
    private let batchManager: BatchManager
    
    private weak var deliveryDelegate: EventDeliveryDelegate?
    private let queue = DispatchQueue(label: "com.trackkit.eventtracker", qos: .utility)
    
    // MARK: - Initialization
    public init(configuration: TrackKitConfiguration, sessionManager: SessionManager) {
        self.configuration = configuration
        self.sessionManager = sessionManager
        self.eventQueue = EventQueue(maxSize: configuration.maxStoredEvents, maxAge: configuration.maxEventAge)
        self.networkManager = NetworkManager(configuration: configuration)
        self.batchManager = BatchManager(configuration: configuration, networkManager: networkManager)
        
        self.networkManager.delegate = self
        self.batchManager.delegate = self
        
        setupPeriodicFlush()
    }
    
    // MARK: - Event Tracking
    
    /// Track an event
    /// - Parameter event: Event to track
    public func track(event: Event) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Enrich event with session info
            let enrichedEvent = self.enrichEvent(event)
            
            // Add to queue
            self.eventQueue.enqueue(enrichedEvent)
            
            TrackKitLogger.logEventTracked(
                eventName: enrichedEvent.name,
                eventType: enrichedEvent.type.rawValue,
                properties: enrichedEvent.properties
            )
            
            // Determine delivery strategy
            self.processEvent(enrichedEvent)
        }
    }
    
    /// Flush all pending events immediately
    public func flush() {
        queue.async { [weak self] in
            self?.flushPendingEvents()
        }
    }
    
    /// Reset tracker state
    public func reset() {
        queue.async { [weak self] in
            self?.eventQueue.clear()
            self?.batchManager.clear()
            TrackKitLogger.info("Event tracker reset")
        }
    }
    
    /// Set batch size
    public func setBatchSize(_ size: Int) {
        batchManager.setBatchSize(size)
    }
    
    /// Set flush interval
    public func setFlushInterval(_ interval: TimeInterval) {
        batchManager.setFlushInterval(interval)
    }
    
    /// Set delivery delegate
    public func setDeliveryDelegate(_ delegate: EventDeliveryDelegate) {
        self.deliveryDelegate = delegate
    }
    
    // MARK: - Private Methods
    
    private func enrichEvent(_ event: Event) -> TrackingEvent {
        return TrackingEvent(
            type: event.type,
            name: event.name,
            properties: event.properties,
            sessionId: sessionManager.sessionId,
            userId: sessionManager.userId,
            priority: determinePriority(for: event)
        )
    }
    
    private func determinePriority(for event: Event) -> EventPriority {
        switch event.type {
        case .error:
            return .critical
        case .session:
            return .high
        case .view, .button:
            return .normal
        case .custom:
            return .normal
        }
    }
    
    private func processEvent(_ event: TrackingEvent) {
        switch event.priority {
        case .critical:
            // Send immediately for critical events
            sendEventImmediately(event)
        case .high:
            // Send with high priority batch
            batchManager.addHighPriorityEvent(event)
        case .normal, .low:
            // Add to regular batch
            batchManager.addEvent(event)
        }
    }
    
    private func sendEventImmediately(_ event: TrackingEvent) {
        let context = RequestContext(
            eventType: event.type,
            deliveryType: .realtime,
            metadata: ["priority": event.priority.rawValue]
        )
        
        networkManager.sendSingleEvent(event, context: context) { [weak self] result in
            DispatchQueue.main.async {
                self?.deliveryDelegate?.didSendEvent(event, success: result.success, error: result.error)
            }
            
            if !result.success {
                // Add to regular queue for retry
                self?.eventQueue.enqueue(event)
            }
        }
    }
    
    private func flushPendingEvents() {
        let events = eventQueue.dequeueAll()
        guard !events.isEmpty else { return }
        
        TrackKitLogger.logBatchOperation(operation: "flush", eventCount: events.count)
        
        let context = RequestContext(
            eventType: .custom,
            deliveryType: .batch,
            metadata: ["forced_flush": true]
        )
        
        networkManager.sendBatch(events, context: context) { [weak self] result in
            DispatchQueue.main.async {
                self?.deliveryDelegate?.didSendBatch(events, success: result.successCount == result.totalEvents, error: nil)
            }
            
            // Re-queue failed events
            if !result.failedEvents.isEmpty {
                let failedEventObjects = events.filter { result.failedEvents.contains($0.id) }
                failedEventObjects.forEach { self?.eventQueue.enqueue($0) }
            }
        }
    }
    
    private func setupPeriodicFlush() {
        Timer.scheduledTimer(withTimeInterval: configuration.flushInterval, repeats: true) { [weak self] _ in
            self?.queue.async {
                let queueSize = self?.eventQueue.count ?? 0
                if queueSize > 0 {
                    TrackKitLogger.debug("Periodic flush triggered, queue size: \(queueSize)")
                    self?.flushPendingEvents()
                }
            }
        }
    }
}

// MARK: - NetworkManagerDelegate
extension EventTracker: NetworkManagerDelegate {
    func networkManager(_ manager: NetworkManager, didCompleteRequest context: RequestContext, result: EventDeliveryResult) {
        // Handle individual request completion
        TrackKitLogger.debug("Request completed: \(result.success ? "success" : "failure")")
    }
    
    func networkManager(_ manager: NetworkManager, didCompleteBatch context: RequestContext, result: BatchDeliveryResult) {
        // Handle batch completion
        TrackKitLogger.debug("Batch completed: \(result.successCount)/\(result.totalEvents) events delivered")
    }
}

// MARK: - BatchManagerDelegate
extension EventTracker: BatchManagerDelegate {
    func batchManager(_ manager: BatchManager, shouldSendBatch events: [TrackingEvent]) -> Bool {
        // Always allow batch sending
        return true
    }
    
    func batchManager(_ manager: BatchManager, didSendBatch events: [TrackingEvent], result: BatchDeliveryResult) {
        DispatchQueue.main.async { [weak self] in
            self?.deliveryDelegate?.didSendBatch(events, success: result.successCount == result.totalEvents, error: nil)
        }
    }
}

// MARK: - Network Manager Protocol
protocol NetworkManagerDelegate: AnyObject {
    func networkManager(_ manager: NetworkManager, didCompleteRequest context: RequestContext, result: EventDeliveryResult)
    func networkManager(_ manager: NetworkManager, didCompleteBatch context: RequestContext, result: BatchDeliveryResult)
}

// MARK: - Batch Manager Protocol
protocol BatchManagerDelegate: AnyObject {
    func batchManager(_ manager: BatchManager, shouldSendBatch events: [TrackingEvent]) -> Bool
    func batchManager(_ manager: BatchManager, didSendBatch events: [TrackingEvent], result: BatchDeliveryResult)
} 