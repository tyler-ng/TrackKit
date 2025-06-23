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
    
    // Track tasks for cancellation
    private var flushTask: Task<Void, Never>?
    private var periodicFlushTimer: Timer?
    
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
    
    deinit {
        flushTask?.cancel()
        periodicFlushTimer?.invalidate()
    }
    
    // MARK: - Event Tracking
    
    /// Track an event
    /// - Parameter event: Event to track
    public func track(event: Event) async {
        // Enrich event with session info
        let enrichedEvent = enrichEvent(event)
        
        // Add to queue
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.eventQueue.enqueue(enrichedEvent)
                continuation.resume()
            }
        }
        
        TrackKitLogger.logEventTracked(
            eventName: enrichedEvent.name,
            eventType: enrichedEvent.type.rawValue,
            properties: enrichedEvent.properties
        )
        
        // Determine delivery strategy
        await processEvent(enrichedEvent)
    }
    
    /// Flush all pending events immediately
    public func flush() async {
        await flushPendingEvents()
    }
    
    /// Reset tracker state
    public func reset() async {
        // Cancel ongoing operations
        flushTask?.cancel()
        
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.eventQueue.clear()
                continuation.resume()
            }
        }
        
        await batchManager.clear()
        
        TrackKitLogger.info("Event tracker reset")
    }
    
    /// Set batch size
    public func setBatchSize(_ size: Int) async {
        await batchManager.setBatchSize(size)
    }
    
    /// Set flush interval
    public func setFlushInterval(_ interval: TimeInterval) async {
        await batchManager.setFlushInterval(interval)
        setupPeriodicFlush() // Restart timer with new interval
    }
    
    /// Set delivery delegate
    public func setDeliveryDelegate(_ delegate: EventDeliveryDelegate) async {
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
    
    private func processEvent(_ event: TrackingEvent) async {
        switch event.priority {
        case .critical:
            // Send immediately for critical events
            await sendEventImmediately(event)
        case .high:
            // Send with high priority batch
            await batchManager.addHighPriorityEvent(event)
        case .normal, .low:
            // Add to regular batch
            await batchManager.addEvent(event)
        }
    }
    
    private func sendEventImmediately(_ event: TrackingEvent) async {
        let context = RequestContext(
            eventType: event.type,
            deliveryType: .realtime,
            metadata: ["priority": event.priority.rawValue]
        )
        
        let result = await networkManager.sendSingleEvent(event, context: context)
        
        // Notify delegate on main thread
        await MainActor.run { [weak self] in
            self?.deliveryDelegate?.didSendEvent(event, success: result.success, error: result.error)
        }
        
        if !result.success {
            // Add to regular queue for retry
            await withCheckedContinuation { continuation in
                queue.async { [weak self] in
                    self?.eventQueue.enqueue(event)
                    continuation.resume()
                }
            }
        }
    }
    
    private func flushPendingEvents() async {
        let events = await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                let events = self?.eventQueue.dequeueAll() ?? []
                continuation.resume(returning: events)
            }
        }
        
        guard !events.isEmpty else { return }
        
        TrackKitLogger.logBatchOperation(operation: "flush", eventCount: events.count)
        
        let context = RequestContext(
            eventType: .custom,
            deliveryType: .batch,
            metadata: ["forced_flush": true]
        )
        
        let result = await networkManager.sendBatch(events, context: context)
        
        // Notify delegate on main thread
        await MainActor.run { [weak self] in
            self?.deliveryDelegate?.didSendBatch(
                events,
                success: result.successCount == result.totalEvents,
                error: result.errors.first
            )
        }
        
        // Re-queue failed events
        if !result.failedEvents.isEmpty {
            let failedEventObjects = events.filter { result.failedEvents.contains($0.id) }
            await withCheckedContinuation { continuation in
                queue.async { [weak self] in
                    failedEventObjects.forEach { self?.eventQueue.enqueue($0) }
                    continuation.resume()
                }
            }
        }
    }
    
    private func setupPeriodicFlush() {
        periodicFlushTimer?.invalidate()
        periodicFlushTimer = Timer.scheduledTimer(withTimeInterval: configuration.flushInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.queue.async {
                let queueSize = self.eventQueue.count
                if queueSize > 0 {
                    TrackKitLogger.debug("Periodic flush triggered, queue size: \(queueSize)")
                    
                    // Cancel previous flush task if running
                    self.flushTask?.cancel()
                    
                    // Start new flush task
                    self.flushTask = Task { [weak self] in
                        await self?.flushPendingEvents()
                    }
                }
            }
        }
    }
    
    // MARK: - Cancellation Support
    
    /// Cancel all ongoing operations
    public func cancelAllOperations() async {
        flushTask?.cancel()
        await batchManager.cancelAllRequests()
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
        Task { [weak self] in
            await MainActor.run {
                self?.deliveryDelegate?.didSendBatch(
                    events,
                    success: result.successCount == result.totalEvents,
                    error: result.errors.first
                )
            }
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