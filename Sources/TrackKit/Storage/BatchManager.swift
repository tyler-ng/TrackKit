import Foundation

/// Manages event batching and delivery optimization
public class BatchManager {
    
    // MARK: - Properties
    private let configuration: TrackKitConfiguration
    private let networkManager: NetworkManager
    weak var delegate: BatchManagerDelegate?
    
    private var regularBatch: [TrackingEvent] = []
    private var highPriorityBatch: [TrackingEvent] = []
    
    private var batchSize: Int
    private var flushInterval: TimeInterval
    private var flushTimer: Timer?
    
    private let queue = DispatchQueue(label: "com.trackkit.batch", qos: .utility)
    
    // MARK: - Initialization
    public init(configuration: TrackKitConfiguration, networkManager: NetworkManager) {
        self.configuration = configuration
        self.networkManager = networkManager
        self.batchSize = configuration.batchSize
        self.flushInterval = configuration.flushInterval
        
        setupFlushTimer()
    }
    
    deinit {
        flushTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Add an event to the regular batch
    /// - Parameter event: Event to add
    public func addEvent(_ event: TrackingEvent) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.regularBatch.append(event)
            TrackKitLogger.debug("Event added to regular batch: \(event.name), batch size: \(self.regularBatch.count)")
            
            if self.regularBatch.count >= self.batchSize {
                self.flushRegularBatch()
            }
        }
    }
    
    /// Add an event to the high priority batch
    /// - Parameter event: Event to add
    public func addHighPriorityEvent(_ event: TrackingEvent) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.highPriorityBatch.append(event)
            TrackKitLogger.debug("Event added to high priority batch: \(event.name), batch size: \(self.highPriorityBatch.count)")
            
            // High priority batches are smaller and sent more frequently
            let highPriorityBatchSize = min(self.batchSize / 2, 25)
            if self.highPriorityBatch.count >= highPriorityBatchSize {
                self.flushHighPriorityBatch()
            }
        }
    }
    
    /// Set batch size
    /// - Parameter size: New batch size
    public func setBatchSize(_ size: Int) {
        queue.async { [weak self] in
            self?.batchSize = max(1, size)
            TrackKitLogger.debug("Batch size updated: \(size)")
        }
    }
    
    /// Set flush interval
    /// - Parameter interval: New flush interval in seconds
    public func setFlushInterval(_ interval: TimeInterval) {
        queue.async { [weak self] in
            self?.flushInterval = max(1.0, interval)
            self?.setupFlushTimer()
            TrackKitLogger.debug("Flush interval updated: \(interval)s")
        }
    }
    
    /// Flush all batches immediately
    public func flushAll() {
        queue.async { [weak self] in
            self?.flushHighPriorityBatch()
            self?.flushRegularBatch()
        }
    }
    
    /// Clear all batches
    public func clear() {
        queue.async { [weak self] in
            self?.regularBatch.removeAll()
            self?.highPriorityBatch.removeAll()
            TrackKitLogger.debug("All batches cleared")
        }
    }
    
    /// Get current batch counts
    public var batchCounts: (regular: Int, highPriority: Int) {
        return queue.sync {
            return (regularBatch.count, highPriorityBatch.count)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.queue.async {
                self?.periodicFlush()
            }
        }
    }
    
    private func periodicFlush() {
        let regularCount = regularBatch.count
        let highPriorityCount = highPriorityBatch.count
        
        if regularCount > 0 || highPriorityCount > 0 {
            TrackKitLogger.debug("Periodic flush triggered - Regular: \(regularCount), High Priority: \(highPriorityCount)")
            
            if highPriorityCount > 0 {
                flushHighPriorityBatch()
            }
            
            if regularCount > 0 {
                flushRegularBatch()
            }
        }
    }
    
    private func flushRegularBatch() {
        guard !regularBatch.isEmpty else { return }
        
        let eventsToSend = regularBatch
        regularBatch.removeAll()
        
        sendBatch(eventsToSend, priority: .normal)
    }
    
    private func flushHighPriorityBatch() {
        guard !highPriorityBatch.isEmpty else { return }
        
        let eventsToSend = highPriorityBatch
        highPriorityBatch.removeAll()
        
        sendBatch(eventsToSend, priority: .high)
    }
    
    private func sendBatch(_ events: [TrackingEvent], priority: EventPriority) {
        guard let delegate = delegate, delegate.batchManager(self, shouldSendBatch: events) else {
            // Re-add events if delegate doesn't allow sending
            queue.async { [weak self] in
                if priority == .high {
                    self?.highPriorityBatch.append(contentsOf: events)
                } else {
                    self?.regularBatch.append(contentsOf: events)
                }
            }
            return
        }
        
        TrackKitLogger.logBatchOperation(operation: "send", eventCount: events.count)
        
        let context = RequestContext(
            eventType: .custom,
            deliveryType: .batch,
            metadata: [
                "batch_priority": priority.rawValue,
                "batch_size": events.count
            ]
        )
        
        networkManager.sendBatch(events, context: context) { [weak self] result in
            guard let self = self else { return }
            
            // Notify delegate
            self.delegate?.batchManager(self, didSendBatch: events, result: result)
            
            // Handle failed events
            if !result.failedEvents.isEmpty {
                let failedEventObjects = events.filter { result.failedEvents.contains($0.id) }
                
                // Re-queue failed events with exponential backoff
                DispatchQueue.main.asyncAfter(deadline: .now() + self.calculateRetryDelay(for: result.errors.count)) {
                    self.queue.async {
                        if priority == .high {
                            self.highPriorityBatch.append(contentsOf: failedEventObjects)
                        } else {
                            self.regularBatch.append(contentsOf: failedEventObjects)
                        }
                        
                        TrackKitLogger.warning("Re-queued \(failedEventObjects.count) failed events for retry")
                    }
                }
            }
        }
    }
    
    private func calculateRetryDelay(for errorCount: Int) -> TimeInterval {
        // Exponential backoff: 2^errorCount seconds, max 60 seconds
        let delay = min(pow(2.0, Double(errorCount)), 60.0)
        return delay
    }
    
    // MARK: - Batch Statistics
    
    /// Get batch statistics
    public var statistics: BatchStatistics {
        return queue.sync {
            return BatchStatistics(
                regularBatchSize: regularBatch.count,
                highPriorityBatchSize: highPriorityBatch.count,
                configuredBatchSize: batchSize,
                flushInterval: flushInterval
            )
        }
    }
}

// MARK: - Batch Statistics

/// Statistics about batch state
public struct BatchStatistics {
    public let regularBatchSize: Int
    public let highPriorityBatchSize: Int
    public let configuredBatchSize: Int
    public let flushInterval: TimeInterval
    
    public var totalPendingEvents: Int {
        return regularBatchSize + highPriorityBatchSize
    }
    
    public var regularBatchFillPercentage: Double {
        guard configuredBatchSize > 0 else { return 0 }
        return Double(regularBatchSize) / Double(configuredBatchSize) * 100
    }
    
    public var highPriorityBatchFillPercentage: Double {
        let highPriorityBatchLimit = max(configuredBatchSize / 2, 25)
        guard highPriorityBatchLimit > 0 else { return 0 }
        return Double(highPriorityBatchSize) / Double(highPriorityBatchLimit) * 100
    }
} 