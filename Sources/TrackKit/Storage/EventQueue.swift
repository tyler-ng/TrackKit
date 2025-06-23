import Foundation

/// Thread-safe event queue with persistence support
public class EventQueue {
    
    // MARK: - Properties
    private var events: [TrackingEvent] = []
    private let maxSize: Int
    private let maxAge: TimeInterval
    private let queue = DispatchQueue(label: "com.trackkit.eventqueue", qos: .utility)
    private let persistenceKey = "TrackKit_EventQueue"
    
    // MARK: - Initialization
    public init(maxSize: Int = 1000, maxAge: TimeInterval = 7 * 24 * 60 * 60) { // 7 days
        self.maxSize = maxSize
        self.maxAge = maxAge
        loadPersistedEvents()
        setupCleanupTimer()
    }
    
    // MARK: - Public Methods
    
    /// Add an event to the queue
    /// - Parameter event: Event to enqueue
    public func enqueue(_ event: TrackingEvent) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.events.append(event)
            self.enforceConstraints()
            self.persistEvents()
            
            TrackKitLogger.debug("Event enqueued: \(event.name), queue size: \(self.events.count)")
        }
    }
    
    /// Remove and return all events from the queue
    /// - Returns: Array of all events
    public func dequeueAll() -> [TrackingEvent] {
        return queue.sync { [weak self] in
            guard let self = self else { return [] }
            
            let allEvents = self.events
            self.events.removeAll()
            self.persistEvents()
            
            TrackKitLogger.debug("Dequeued all events: \(allEvents.count)")
            return allEvents
        }
    }
    
    /// Remove and return a specific number of events
    /// - Parameter count: Number of events to dequeue
    /// - Returns: Array of events
    public func dequeue(count: Int) -> [TrackingEvent] {
        return queue.sync { [weak self] in
            guard let self = self else { return [] }
            
            let eventsToReturn = Array(self.events.prefix(count))
            self.events.removeFirst(min(count, self.events.count))
            self.persistEvents()
            
            TrackKitLogger.debug("Dequeued \(eventsToReturn.count) events, remaining: \(self.events.count)")
            return eventsToReturn
        }
    }
    
    /// Get the current number of events in the queue
    public var count: Int {
        return queue.sync { events.count }
    }
    
    /// Check if the queue is empty
    public var isEmpty: Bool {
        return queue.sync { events.isEmpty }
    }
    
    /// Clear all events from the queue
    public func clear() {
        queue.async { [weak self] in
            self?.events.removeAll()
            self?.persistEvents()
            TrackKitLogger.debug("Event queue cleared")
        }
    }
    
    /// Get events by type
    /// - Parameter type: Event type to filter by
    /// - Returns: Array of events of the specified type
    public func events(ofType type: EventType) -> [TrackingEvent] {
        return queue.sync { events.filter { $0.type == type } }
    }
    
    /// Get events by priority
    /// - Parameter priority: Priority level to filter by
    /// - Returns: Array of events with the specified priority
    public func events(withPriority priority: EventPriority) -> [TrackingEvent] {
        return queue.sync { events.filter { $0.priority == priority } }
    }
    
    // MARK: - Private Methods
    
    private func enforceConstraints() {
        // Remove old events
        let cutoffTime = Date().addingTimeInterval(-maxAge)
        events = events.filter { $0.timestamp > cutoffTime }
        
        // Enforce size limit (remove oldest events first)
        if events.count > maxSize {
            let eventsToRemove = events.count - maxSize
            events.removeFirst(eventsToRemove)
            TrackKitLogger.warning("Event queue size limit exceeded, removed \(eventsToRemove) oldest events")
        }
    }
    
    private func setupCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in // Every hour
            self?.queue.async {
                let oldCount = self?.events.count ?? 0
                self?.enforceConstraints()
                let newCount = self?.events.count ?? 0
                
                if oldCount != newCount {
                    self?.persistEvents()
                    TrackKitLogger.debug("Cleaned up \(oldCount - newCount) expired events")
                }
            }
        }
    }
    
    // MARK: - Persistence
    
    private func persistEvents() {
        do {
            let eventsData = try JSONEncoder().encode(events.map { EventData(from: $0) })
            UserDefaults.standard.set(eventsData, forKey: persistenceKey)
        } catch {
            TrackKitLogger.error("Failed to persist events: \(error)")
        }
    }
    
    private func loadPersistedEvents() {
        guard let eventsData = UserDefaults.standard.data(forKey: persistenceKey) else { return }
        
        do {
            let eventDataArray = try JSONDecoder().decode([EventData].self, from: eventsData)
            events = eventDataArray.compactMap { $0.toTrackingEvent() }
            
            // Clean up old events after loading
            enforceConstraints()
            
            TrackKitLogger.debug("Loaded \(events.count) persisted events")
        } catch {
            TrackKitLogger.error("Failed to load persisted events: \(error)")
            // Clear corrupted data
            UserDefaults.standard.removeObject(forKey: persistenceKey)
        }
    }
}

// MARK: - EventData for Persistence

/// Codable wrapper for TrackingEvent to enable persistence
private struct EventData: Codable {
    let id: String
    let timestamp: Date
    let type: String
    let name: String
    let properties: Data // JSON encoded
    let sessionId: String?
    let userId: String?
    let deviceInfo: Data // JSON encoded
    let appInfo: Data // JSON encoded
    let priority: Int
    
    init(from event: TrackingEvent) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.type = event.type.rawValue
        self.name = event.name
        self.sessionId = event.sessionId
        self.userId = event.userId
        self.priority = event.priority.rawValue
        
        // Encode dictionaries as JSON data
        self.properties = (try? JSONSerialization.data(withJSONObject: event.properties)) ?? Data()
        self.deviceInfo = (try? JSONSerialization.data(withJSONObject: event.deviceInfo)) ?? Data()
        self.appInfo = (try? JSONSerialization.data(withJSONObject: event.appInfo)) ?? Data()
    }
    
    func toTrackingEvent() -> TrackingEvent? {
        guard let eventType = EventType(rawValue: type),
              let eventPriority = EventPriority(rawValue: priority) else {
            return nil
        }
        
        // Decode dictionaries from JSON data
        let properties = (try? JSONSerialization.jsonObject(with: self.properties) as? [String: Any]) ?? [:]
        let deviceInfo = (try? JSONSerialization.jsonObject(with: self.deviceInfo) as? [String: Any]) ?? [:]
        let appInfo = (try? JSONSerialization.jsonObject(with: self.appInfo) as? [String: Any]) ?? [:]
        
        return TrackingEvent(
            type: eventType,
            name: name,
            properties: properties,
            sessionId: sessionId,
            userId: userId,
            priority: eventPriority
        )
    }
} 