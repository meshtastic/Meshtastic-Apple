//
//  MessageRetryQueueManager.swift
//  Meshtastic
//
//  Retry queue manager using Swift actors and Task scheduling
//

import Foundation
import CoreData
import MeshtasticProtobufs
import OSLog
import Combine

enum MessageType: String, Codable, CaseIterable {
    case text = "text"
    case position = "position"
    case waypoint = "waypoint"
    case admin = "admin"
    case traceroute = "traceroute"
    case nodeInfo = "nodeInfo"
    case unknown = "unknown"
}

enum RetryState: String, Codable {
    case pending = "pending"
    case sending = "sending"
    case waitingForAck = "waitingForAck"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

struct RetryQueueItem: Identifiable, Hashable {
    let id: UUID
    let originalMessageId: Int64
    let messageType: MessageType
    let serializedPacket: Data?  // Full MeshPacket serialized for retry
    let createdAt: Date
    
    var retryCount: Int
    var state: RetryState
    var nextRetryDate: Date
	var lastError: String?
	var currentPacketId: UInt32? // Track the current packet ID being sent for ACK lookup
	var packetIdHistory: [UInt32] // Track all packet IDs associated with this retry chain

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
	init(
		id: UUID = UUID(),
		originalMessageId: Int64,
		messageType: MessageType,
		serializedPacket: Data? = nil
	) {
        self.id = id
        self.originalMessageId = originalMessageId
        self.messageType = messageType
        self.serializedPacket = serializedPacket
        self.createdAt = Date()
        
        // If an item is in the retry queue, we're scheduling at least the first retry.
        // retryCount is 1-based: 1 = first retry (attempt 2/3), 2 = second retry (attempt 3/3)
        self.retryCount = 1
        self.state = .pending
        self.nextRetryDate = Date().addingTimeInterval(messageType == .traceroute ? 30 : 10)
		self.currentPacketId = nil
		self.packetIdHistory = [UInt32(truncatingIfNeeded: originalMessageId)]
	}
    
    // Convenience initializers for backwards compatibility
	init(
        id: UUID = UUID(),
        originalMessageId: Int64,
        messageType: MessageType,
        payload: Data,
        portNum: PortNum,
        toUserNum: Int64,
        channel: Int32,
        isEmoji: Bool = false,
        replyID: Int64 = 0,
        pkiEncrypted: Bool = false,
        publicKey: Data? = nil,
        originalPayload: String? = nil,
        hopLimit: UInt32? = nil
	) {
        self.id = id
        self.originalMessageId = originalMessageId
        self.messageType = messageType
        self.serializedPacket = nil
        self.createdAt = Date()
        
        self.retryCount = 1
        self.state = .pending
        self.nextRetryDate = Date().addingTimeInterval(messageType == .traceroute ? 30 : 10)
		self.currentPacketId = nil
		self.packetIdHistory = [UInt32(truncatingIfNeeded: originalMessageId)]
	}

	var normalizedRetryCount: Int { max(1, retryCount) }

    // Display attempt number: original send = 1, first retry = 2, second retry = 3
	var displayAttemptNumber: Int {
		normalizedRetryCount + 1
	}

	func matchesPacketId(_ packetId: UInt32) -> Bool {
		currentPacketId == packetId || packetIdHistory.contains(packetId)
	}
    
    static func == (lhs: RetryQueueItem, rhs: RetryQueueItem) -> Bool {
        lhs.id == rhs.id
    }
}

actor MessageRetryQueueManager {
    static let shared = MessageRetryQueueManager()
	
	// Posted whenever queue state changes (for UI refresh)
	nonisolated static let didUpdateNotification = Foundation.Notification.Name("MessageRetryQueueManager.didUpdate")
    
    private var queue: [RetryQueueItem] = []
    private var failedMessageIds: Set<Int64> = [] // Track messages that have exhausted retries
    private var processingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    private(set) var pendingCount: Int = 0

    let maxRetries = 2
    private let retryDelays: [TimeInterval] = [10, 20] // First retry at 10s, second at 20s
    private let tracerouteRetryDelays: [TimeInterval] = [30, 60] // Traceroute retries with 30s and 60s delays
    private let minimumRetrySpacing: TimeInterval = 10
    private let queueProcessingInterval: TimeInterval = 1.0
    private let tracerouteCooldown: TimeInterval = 30.0 // Traceroute has 30s rate limit
    
    private var lastTracerouteRetryTime: Date?

	private func setCurrentPacketId(for itemId: UUID, packetId: UInt32) {
		if let index = queue.firstIndex(where: { $0.id == itemId }) {
			queue[index].currentPacketId = packetId
			if !queue[index].packetIdHistory.contains(packetId) {
				queue[index].packetIdHistory.append(packetId)
			}
			notifyUpdate()
		}
	}
	
	private func notifyUpdate() {
		Task { @MainActor in
			NotificationCenter.default.post(name: MessageRetryQueueManager.didUpdateNotification, object: nil)
		}
	}
    
    private init() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.startQueueProcessor()
        }
    }
    
    func startQueueProcessor() {
        guard processingTask == nil else { return }
        
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                await self.processQueue()
                try? await Task.sleep(nanoseconds: UInt64(self.queueProcessingInterval * 1_000_000_000))
            }
        }
        Logger.mesh.info("📬 Message retry queue processor started")
    }
    
    func stopQueueProcessor() {
        processingTask?.cancel()
        processingTask = nil
        Logger.mesh.info("📬 Message retry queue processor stopped")
		notifyUpdate()
    }
    
    func processQueue() async {
        guard await AccessoryManager.shared.isConnected else {
            return
        }
        
        let now = Date()
        var itemsToProcess: [RetryQueueItem] = []
        
        for item in queue where item.state == .pending && item.nextRetryDate <= now {
            // Check traceroute cooldown
            if item.messageType == .traceroute, let lastTime = lastTracerouteRetryTime {
                let timeSinceLastTraceroute = now.timeIntervalSince(lastTime)
                if timeSinceLastTraceroute < tracerouteCooldown {
                    // Skip this traceroute retry, will be picked up in next processing cycle
                    continue
                }
            }
            itemsToProcess.append(item)
        }
        
        for item in itemsToProcess {
            guard !Task.isCancelled else { break }
            
            // Update traceroute cooldown tracker
            if item.messageType == .traceroute {
                lastTracerouteRetryTime = Date()
            }
            
            await processItem(item)
        }
        
        self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
    }
    
    private func processItem(_ item: RetryQueueItem) async {
        guard item.state == .pending else { return }
        
        updateItemState(item.id, state: .sending)
        
        do {
            switch item.messageType {
            case .text:
                if item.serializedPacket != nil {
                    try await resendFromSerializedPacket(item)
                } else {
                    try await resendTextMessage(item)
                }
            case .position:
                try await resendPositionMessage(item)
            case .waypoint:
                if item.serializedPacket != nil {
                    try await resendFromSerializedPacket(item)
                } else {
                    try await resendWaypointMessage(item)
                }
            case .admin:
                if item.serializedPacket != nil {
                    try await resendFromSerializedPacket(item)
                } else {
                    Logger.mesh.warning("Admin message retry with no payload")
                    updateItemState(item.id, state: .failed)
                    return
                }
            case .traceroute:
                try await resendTracerouteMessage(item)
            case .nodeInfo:
                if item.serializedPacket != nil {
                    try await resendFromSerializedPacket(item)
                } else {
                    Logger.mesh.warning("Node info retry with no payload")
                    updateItemState(item.id, state: .failed)
                    return
                }
            case .unknown:
                if item.serializedPacket != nil {
                    try await resendFromSerializedPacket(item)
                } else {
                    Logger.mesh.warning("Unknown message retry with no payload")
                    updateItemState(item.id, state: .failed)
                    return
                }
            }
            
            updateItemState(item.id, state: .waitingForAck)

            Logger.mesh.info("📬 Message \(item.originalMessageId) attempt \(item.displayAttemptNumber)/\(self.maxRetries + 1) sent successfully")
            
        } catch {
            Logger.mesh.error("📬 Failed to retry message \(item.originalMessageId): \(error.localizedDescription, privacy: .public)")
            
            let newRetryCount = item.normalizedRetryCount + 1
            if newRetryCount > maxRetries {
                updateItemState(item.id, state: .failed)
                updateItemError(item.id, error: error.localizedDescription)
                // Track that this message has exhausted its retries
                failedMessageIds.insert(item.originalMessageId)
            } else {
                let delay = retryDelay(for: item.messageType, retryCount: newRetryCount)
                updateItemRetry(item.id, retryCount: newRetryCount, nextRetryDate: Date().addingTimeInterval(delay))
                updateItemState(item.id, state: .pending)
            }
        }
    }
    
    private func retryDelay(for messageType: MessageType, retryCount: Int) -> TimeInterval {
        switch messageType {
        case .traceroute:
            return tracerouteRetryDelays[safe: retryCount - 1] ?? tracerouteCooldown
        default:
            return retryDelays[safe: retryCount - 1] ?? 20
        }
    }
    
	private func resendFromSerializedPacket(_ item: RetryQueueItem) async throws {
        guard let serializedData = item.serializedPacket else {
            throw AccessoryError.appError("No serialized packet for retry")
        }
        
        var meshPacket = try MeshPacket(serializedData: serializedData)
        let newMessageId = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
        meshPacket.id = newMessageId
        
		setCurrentPacketId(for: item.id, packetId: newMessageId)
        
        var toRadio = ToRadio()
        toRadio.packet = meshPacket
        
        try await AccessoryManager.shared.send(toRadio, debugDescription: "Retry \(item.messageType) for message \(item.originalMessageId)")
    }
    
	private func resendTextMessage(_ item: RetryQueueItem) async throws {
        // Try to get the original message from the database
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "messageId == %lld", item.originalMessageId)
        
        var originalPayload: String?
        var channel: Int32 = 0
        var isEmoji: Bool = false
        var replyID: Int64 = 0
        var toUserNum: Int64 = 0
        
        do {
            let fetchedMessages = try context.fetch(fetchRequest)
            if let message = fetchedMessages.first {
                originalPayload = message.messagePayload
                channel = message.channel
                isEmoji = message.isEmoji
                replyID = message.replyID
                toUserNum = message.toUser?.num ?? 0
            }
        } catch {
            Logger.mesh.error("📬 Failed to fetch message for retry: \(error.localizedDescription, privacy: .public)")
        }
        
        guard originalPayload != nil else {
            throw AccessoryError.appError("Missing message payload")
        }
        
        let newMessageId = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
        
		setCurrentPacketId(for: item.id, packetId: newMessageId)
        
        var meshPacket = MeshPacket()
        meshPacket.id = newMessageId
        
        if toUserNum > 0 {
            meshPacket.to = UInt32(toUserNum)
        } else {
            meshPacket.to = Constants.maximumNodeNum
        }
        
        meshPacket.channel = UInt32(channel)
        meshPacket.from = UInt32(await AccessoryManager.shared.activeDeviceNum ?? 0)
        meshPacket.wantAck = true
        
        var dataMessage = DataMessage()
        if let payloadData = originalPayload?.data(using: .utf8) {
            dataMessage.payload = payloadData
        }
        dataMessage.portnum = .textMessageApp
        dataMessage.emoji = isEmoji ? 1 : 0
        if replyID > 0 {
            dataMessage.replyID = UInt32(replyID)
        }
        
        meshPacket.decoded = dataMessage
        
        var toRadio = ToRadio()
        toRadio.packet = meshPacket
        try await AccessoryManager.shared.send(toRadio, debugDescription: "Retry message \(item.originalMessageId) -> \(newMessageId)")
    }
    
	private func resendPositionMessage(_ item: RetryQueueItem) async throws {
        guard let fromNodeNum = await AccessoryManager.shared.activeConnection?.device.num else {
            throw AccessoryError.ioFailed("Not connected to any device")
        }
        
        guard let positionPacket = try await AccessoryManager.shared.getPositionFromPhoneGPS(destNum: fromNodeNum, fixedPosition: false) else {
            throw AccessoryError.appError("Unable to get position data")
        }
        
        var meshPacket = MeshPacket()
        let newMessageId = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
        meshPacket.id = newMessageId
        meshPacket.to = Constants.maximumNodeNum
        meshPacket.channel = 0
        meshPacket.from = UInt32(fromNodeNum)
        meshPacket.wantAck = true
        
		setCurrentPacketId(for: item.id, packetId: newMessageId)
        
        var dataMessage = DataMessage()
        if let serializedData = try? positionPacket.serializedData() {
            dataMessage.payload = serializedData
            dataMessage.portnum = PortNum.positionApp
            meshPacket.decoded = dataMessage
        } else {
            throw AccessoryError.ioFailed("Failed to serialize position packet")
        }
        
        var toRadio = ToRadio()
        toRadio.packet = meshPacket
        try await AccessoryManager.shared.send(toRadio, debugDescription: "Retry position for message \(item.originalMessageId)")
    }
    
	private func resendWaypointMessage(_ item: RetryQueueItem) async throws {
        Logger.mesh.warning("📬 Waypoint retry - requires serialized packet for full implementation")
        
        guard let serializedData = item.serializedPacket else {
            throw AccessoryError.appError("No serialized packet for waypoint retry")
        }
        
        var meshPacket = try MeshPacket(serializedData: serializedData)
        let newMessageId = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
        meshPacket.id = newMessageId
        
		setCurrentPacketId(for: item.id, packetId: newMessageId)
        
        var toRadio = ToRadio()
        toRadio.packet = meshPacket
        try await AccessoryManager.shared.send(toRadio, debugDescription: "Retry waypoint for message \(item.originalMessageId)")
    }
    
	private func resendTracerouteMessage(_ item: RetryQueueItem) async throws {
        guard let fromNodeNum = await AccessoryManager.shared.activeConnection?.device.num else {
            throw AccessoryError.ioFailed("Not connected to any device")
        }
        
        let routePacket = RouteDiscovery()
        var meshPacket = MeshPacket()
        let newMessageId = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
        meshPacket.id = newMessageId
        
        meshPacket.to = Constants.maximumNodeNum
        meshPacket.from = UInt32(fromNodeNum)
        meshPacket.channel = 0
        meshPacket.wantAck = true
        
        var dataMessage = DataMessage()
        if let serializedData = try? routePacket.serializedData() {
            dataMessage.payload = serializedData
            dataMessage.portnum = PortNum.tracerouteApp
            dataMessage.wantResponse = true
            meshPacket.decoded = dataMessage
        } else {
            throw AccessoryError.ioFailed("Failed to serialize traceroute packet")
        }
        
		setCurrentPacketId(for: item.id, packetId: newMessageId)
        
        var toRadio = ToRadio()
        toRadio.packet = meshPacket
        
        try await AccessoryManager.shared.send(toRadio, debugDescription: "Retry traceroute for message \(item.originalMessageId)")
        
        // Update TraceRouteEntity with the new packet ID
        let context = PersistenceController.shared.container.viewContext
        let traceRequest = TraceRouteEntity.fetchRequest()
        traceRequest.predicate = NSPredicate(format: "id == %lld", item.originalMessageId)
        
        do {
            let fetchedRoutes = try context.fetch(traceRequest)
            var targetNodeNum: Int64 = 0
            for route in fetchedRoutes {
                targetNodeNum = route.node?.num ?? 0
                context.delete(route)
            }
            
            let newTraceRoute = TraceRouteEntity(context: context)
            newTraceRoute.id = Int64(newMessageId)
            newTraceRoute.time = Date()
            newTraceRoute.sent = true
            
            if targetNodeNum > 0 {
                let nodesRequest = NodeInfoEntity.fetchRequest()
                nodesRequest.predicate = NSPredicate(format: "num == %lld", targetNodeNum)
                if let nodes = try? context.fetch(nodesRequest), let node = nodes.first {
                    newTraceRoute.node = node
                }
            }
            
            try context.save()
            Logger.mesh.info("📬 Created replacement TraceRouteEntity with new ID \(newMessageId) for retry of \(item.originalMessageId)")
        } catch {
            Logger.mesh.error("📬 Failed to update TraceRouteEntity for retry: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Queue Management
    
	func addToQueue(
        originalMessageId: Int64,
        messageType: MessageType,
        payload: Data,
        portNum: PortNum,
        toUserNum: Int64,
        channel: Int32,
        isEmoji: Bool = false,
        replyID: Int64 = 0,
        pkiEncrypted: Bool = false,
        publicKey: Data? = nil,
        originalPayload: String? = nil,
        hopLimit: UInt32? = nil
    ) {
        // Don't add if this message has already exhausted its retries
        if failedMessageIds.contains(originalMessageId) {
            Logger.mesh.info("📬 Message \(originalMessageId) has exhausted retries, not re-adding to queue")
            return
        }
        
		let originalPacketId = UInt32(truncatingIfNeeded: originalMessageId)
		// Check if already in queue by original message ID / any known packet ID
		if queue.contains(where: { $0.originalMessageId == originalMessageId || $0.matchesPacketId(originalPacketId) }) {
			return
		}
		
		// Check if we have an existing item with this packet ID (late routing for a prior retry)
		if let existingItem = queue.first(where: { $0.matchesPacketId(originalPacketId) }) {
			Logger.mesh.info("📬 Message with packet ID \(originalMessageId) is already being tracked (original: \(existingItem.originalMessageId))")
			return
		}
        
        let item = RetryQueueItem(
            originalMessageId: originalMessageId,
            messageType: messageType,
            payload: payload,
            portNum: portNum,
            toUserNum: toUserNum,
            channel: channel,
            isEmoji: isEmoji,
            replyID: replyID,
            pkiEncrypted: pkiEncrypted,
            publicKey: publicKey,
            originalPayload: originalPayload,
            hopLimit: hopLimit
        )
        
		queue.append(item)
		self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
		Logger.mesh.info("📬 Added message \(originalMessageId) to retry queue (retry 1/\(self.maxRetries + 1) in 10s)")
		notifyUpdate()
	}
    
	func cancelRetry(for messageId: Int64) {
		if let index = queue.firstIndex(where: { $0.originalMessageId == messageId }) {
			queue[index].state = .cancelled
			self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
			Logger.mesh.info("📬 Cancelled retry for message \(messageId)")
			notifyUpdate()
		}
	}
    
	func cancelRetry(forItemId itemId: UUID) {
		if let index = queue.firstIndex(where: { $0.id == itemId }) {
			queue[index].state = .cancelled
			self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
			Logger.mesh.info("📬 Cancelled retry for item \(itemId)")
			notifyUpdate()
		}
	}
    
	func clearAllRetries() {
		for index in queue.indices {
			queue[index].state = .cancelled
		}
		self.pendingCount = 0
		Logger.mesh.info("📬 Cleared all pending retries")
		notifyUpdate()
	}
    
	func markCompleted(for messageId: Int64) {
		if let index = queue.firstIndex(where: { $0.originalMessageId == messageId }) {
			queue[index].state = .completed
			self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
			Logger.mesh.info("📬 Marked message \(messageId) as completed")
			notifyUpdate()
		}
	}
    
	func markFailed(for messageId: Int64, error: String? = nil) {
		if let index = queue.firstIndex(where: { $0.originalMessageId == messageId }) {
			queue[index].state = .failed
			if let error = error {
				queue[index].lastError = error
			}
			// Track that this message has exhausted its retries
			failedMessageIds.insert(messageId)
			self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
			Logger.mesh.info("📬 Marked message \(messageId) as failed")
			notifyUpdate()
		}
	}
    
	func removeCompleted() {
		queue.removeAll { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }
		self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
		notifyUpdate()
	}
    
	func clearAll() {
		queue.removeAll()
		self.pendingCount = 0
		Logger.mesh.info("📬 Cleared all pending retries")
		notifyUpdate()
	}
    
    func getQueue() -> [RetryQueueItem] {
        return queue
    }
    
    func getPendingItems() -> [RetryQueueItem] {
        return queue.filter { $0.state == .pending || $0.state == .waitingForAck }
    }
    
	func getStatus(for messageId: Int64) -> RetryState? {
		if let item = queue.first(where: { $0.originalMessageId == messageId }) {
			return item.state
		}
		let packetId = UInt32(truncatingIfNeeded: messageId)
		if let item = queue.first(where: { $0.matchesPacketId(packetId) }) {
			return item.state
		}
		return nil
	}
    
    func addToRetryQueue(_ item: RetryQueueItem) {
        queue.append(item)
        pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
        Logger.mesh.info("📬 Added message \(item.originalMessageId) to retry queue (retry 1/\(self.maxRetries + 1) in 10s)")
		notifyUpdate()
    }

	func getRetryStatus(for messageId: Int64) -> (current: Int, max: Int, state: RetryState)? {
		if let item = queue.first(where: { $0.originalMessageId == messageId }) {
			return (item.displayAttemptNumber, maxRetries + 1, item.state)
		}
		let packetId = UInt32(truncatingIfNeeded: messageId)
		if let item = queue.first(where: { $0.matchesPacketId(packetId) }) {
			return (item.displayAttemptNumber, maxRetries + 1, item.state)
		}
		return nil
	}

	func originalMessageId(forPacketId packetId: UInt32) -> Int64? {
		queue.first(where: { $0.matchesPacketId(packetId) })?.originalMessageId
	}
    
	func markCompletedByPacketId(_ packetId: UInt32) {
		// Check both original message ID and current packet ID
		if let index = queue.firstIndex(where: { $0.matchesPacketId(packetId) }) {
			queue[index].state = .completed
			self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
			Logger.mesh.info("📬 Marked message with packet ID \(packetId) as completed (retry)")
			notifyUpdate()
		}
	}
    
	func canRetry(_ messageId: Int64) -> Bool {
        // Check if message has already exhausted its retries
        if failedMessageIds.contains(messageId) {
            return false
        }
        
		// Check by original message ID
		if let item = queue.first(where: { $0.originalMessageId == messageId }) {
			return item.state == .pending || item.state == .waitingForAck || item.state == .sending
		}
		
		// Also check by any known packet ID (for retries that created new packet IDs)
		let packetId = UInt32(truncatingIfNeeded: messageId)
		if let item = queue.first(where: { $0.matchesPacketId(packetId) }) {
			return item.state == .pending || item.state == .waitingForAck || item.state == .sending
		}
        
        return false
    }
    
    /// Handle a NACK for a packet - finds existing item and increments retry count
	func handleNack(for packetId: Int64) {
        // Check if message has already exhausted its retries
        if failedMessageIds.contains(packetId) {
            Logger.mesh.info("📬 Message \(packetId) has exhausted retries, ignoring NACK")
            return
        }
        
		let pid = UInt32(truncatingIfNeeded: packetId)

		// Prefer matching by current packet ID / history (covers late routing for older retry packets)
		if let index = queue.firstIndex(where: { $0.matchesPacketId(pid) }) {
			let item = queue[index]
			// If this NACK is for an older packet ID, but we're currently waiting on a newer packet,
			// ignore it so we don't flip the UI to failed while the latest attempt is in-flight.
			if item.currentPacketId != nil, item.currentPacketId != pid,
			   (item.state == .sending || item.state == .waitingForAck) {
				Logger.mesh.info("📬 Ignoring stale NACK for packet \(packetId) (current: \(String(describing: item.currentPacketId)))")
				return
			}
			handleNackForItem(at: index)
			return
		}
        
		// Message not in queue - this is the first NACK, add it to queue
		Logger.mesh.info("📬 First NACK for packet \(packetId), adding to retry queue")
		addNewRetryForPacket(packetId)
	}
    
	private func addNewRetryForPacket(_ packetId: Int64) {
        // Try to find message data to create a proper retry item
        let context = PersistenceController.shared.container.viewContext
        
        // Try to find a MessageEntity with this ID (text messages)
        let fetchRequest = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "messageId == %lld", packetId)
        
        do {
            let fetchedMessages = try context.fetch(fetchRequest)
            if let message = fetchedMessages.first {
                // Clear error status so UI shows retry state
                message.ackError = 0
                message.receivedACK = false
                message.ackTimestamp = 0
                try context.save()
                
                // Found message entity, create retry with full data
                let payloadData = message.messagePayload?.data(using: .utf8) ?? Data()
                let item = RetryQueueItem(
                    originalMessageId: packetId,
                    messageType: .text,
                    payload: payloadData,
                    portNum: .textMessageApp,
                    toUserNum: message.toUser?.num ?? 0,
                    channel: message.channel,
                    isEmoji: message.isEmoji,
                    replyID: message.replyID,
                    pkiEncrypted: message.pkiEncrypted,
                    publicKey: message.publicKey,
                    originalPayload: message.messagePayload
                )
                queue.append(item)
                Logger.mesh.info("📬 Added text message \(packetId) to retry queue (retry 1/\(self.maxRetries + 1) in 10s)")
            } else {
                // Check if it's a traceroute message
                let traceRequest = TraceRouteEntity.fetchRequest()
                traceRequest.predicate = NSPredicate(format: "id == %lld", packetId)
                do {
                    let fetchedRoutes = try context.fetch(traceRequest)
                    if let traceRoute = fetchedRoutes.first {
                        // Clear error status
                        traceRoute.sent = true
                        try context.save()
                        
                        let item = RetryQueueItem(
                            originalMessageId: packetId,
                            messageType: .traceroute,
                            payload: Data(),
                            portNum: .tracerouteApp,
                            toUserNum: traceRoute.node?.num ?? 0,
                            channel: 0
                        )
                        queue.append(item)
                        Logger.mesh.info("📬 Added traceroute \(packetId) to retry queue (retry 1/\(self.maxRetries + 1) in 30s)")
                    } else {
                        // No entity found - create basic unknown retry
                        // The actual resend will fail gracefully if no serialized packet
                        let item = RetryQueueItem(
                            originalMessageId: packetId,
                            messageType: .unknown
                        )
                        queue.append(item)
                        Logger.mesh.info("📬 Added unknown packet \(packetId) to retry queue (basic, retry 1/\(self.maxRetries + 1) in 10s)")
                    }
                } catch {
                    // No traceroute found, create basic unknown retry
                    let item = RetryQueueItem(
                        originalMessageId: packetId,
                        messageType: .unknown
                    )
                    queue.append(item)
                    Logger.mesh.info("📬 Added packet \(packetId) to retry queue (fallback, retry 1/\(self.maxRetries + 1) in 10s)")
                }
            }
				self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
		} catch {
            // Even on error, add basic unknown item
            let item = RetryQueueItem(
                originalMessageId: packetId,
                messageType: .unknown
            )
            queue.append(item)
            self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
            Logger.mesh.error("📬 Failed to fetch message for retry, added basic item: \(error.localizedDescription, privacy: .public)")
        }
    }
    
	private func handleNackForItem(at index: Int) {
        let item = queue[index]
        let newRetryCount = item.normalizedRetryCount + 1
        
        if newRetryCount > self.maxRetries {
            // Exhausted retries
            queue[index].state = .failed
            failedMessageIds.insert(item.originalMessageId)
            Logger.mesh.info("📬 Message \(item.originalMessageId) exhausted \(self.maxRetries) retries, marking as failed")
        } else {
            // Increment retry count and reschedule
            let delay = retryDelay(for: item.messageType, retryCount: newRetryCount)
            queue[index].retryCount = newRetryCount
            queue[index].nextRetryDate = Date().addingTimeInterval(delay)
            queue[index].state = .pending
			queue[index].currentPacketId = nil // Will be set when retry is sent
            
            // Clear the error in the database so UI shows retry state instead of error
            clearMessageError(for: item.originalMessageId)
            
            Logger.mesh.info("📬 Message \(item.originalMessageId) NACK received, retry \(newRetryCount)/\(self.maxRetries + 1) scheduled in \(Int(delay))s")
        }
        
		self.pendingCount = queue.filter { $0.state == .pending || $0.state == .waitingForAck || $0.state == .sending }.count
		notifyUpdate()
    }
    
    private func clearMessageError(for messageId: Int64) {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "messageId == %lld", messageId)
        
        do {
            let messages = try context.fetch(fetchRequest)
            for message in messages {
                message.ackError = 0
                message.receivedACK = false
                message.ackTimestamp = 0
            }
            try context.save()
            Logger.mesh.info("📬 Cleared error status for message \(messageId) during retry")
        } catch {
            Logger.mesh.error("📬 Failed to clear message error: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Private Helpers
    
	private func updateItemState(_ itemId: UUID, state: RetryState) {
        if let index = queue.firstIndex(where: { $0.id == itemId }) {
            queue[index].state = state
			notifyUpdate()
        }
    }
    
    private func updateItemRetry(_ itemId: UUID, retryCount: Int, nextRetryDate: Date) {
        if let index = queue.firstIndex(where: { $0.id == itemId }) {
            queue[index].retryCount = retryCount
            queue[index].nextRetryDate = nextRetryDate
			notifyUpdate()
        }
    }
    
    private func updateItemError(_ itemId: UUID, error: String) {
        if let index = queue.firstIndex(where: { $0.id == itemId }) {
            queue[index].lastError = error
			notifyUpdate()
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
