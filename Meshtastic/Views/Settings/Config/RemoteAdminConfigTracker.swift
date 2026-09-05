//
//  RemoteAdminConfigTracker.swift
//  Meshtastic
//

import Combine
import Foundation
import MeshtasticProtobufs

enum RemoteAdminConfigOperationKind: Equatable {
	case request
	case save
	case action
}

enum RemoteAdminConfigOperationResult: Equatable {
	case succeeded
	case acknowledged
	case failed(String)
	case timedOut
	case unconfirmed
}

struct RemoteAdminConfigOperation: Identifiable, Equatable {
	let id: UUID
	let sequence: UInt64
	let kind: RemoteAdminConfigOperationKind
	let targetNodeNum: Int64
	let section: String
	var pendingPacketIDs: Set<UInt32> = []
	var result: RemoteAdminConfigOperationResult?

	var isFinished: Bool { result != nil }
}

/// Tracks only explicitly enrolled remote-admin work. The operation token is carried through the
/// async request/save closure with TaskLocal, so unrelated admin packets can never be enrolled by
/// target-node coincidence.
@MainActor
final class RemoteAdminConfigTracker: ObservableObject {
	@TaskLocal static var currentOperationID: UUID?

	@Published private(set) var operations: [UUID: RemoteAdminConfigOperation] = [:]
	private var nextSequence: UInt64 = 0

	static func isAdminResponse(_ message: AdminMessage) -> Bool {
		switch message.payloadVariant {
		case .getChannelResponse, .getOwnerResponse, .getConfigResponse, .getModuleConfigResponse,
				.getCannedMessageModuleMessagesResponse, .getDeviceMetadataResponse, .getRingtoneResponse,
				.getDeviceConnectionStatusResponse, .getNodeRemoteHardwarePinsResponse, .getUiConfigResponse:
			return true
		default:
			return false
		}
	}

	@discardableResult
	func begin(kind: RemoteAdminConfigOperationKind, targetNodeNum: Int64, section: String = "save") -> UUID? {
		if operations.values.contains(where: {
			$0.kind == kind && $0.targetNodeNum == targetNodeNum && $0.section == section && !$0.isFinished
		}) { return nil }
		nextSequence += 1
		let id = UUID()
		operations[id] = RemoteAdminConfigOperation(id: id, sequence: nextSequence, kind: kind, targetNodeNum: targetNodeNum, section: section)
		return id
	}

	func registerPacket(packetID: UInt32, targetNodeNum: Int64, operationID: UUID?) -> Bool {
		guard let operationID, var operation = operations[operationID], !operation.isFinished,
			  operation.targetNodeNum == targetNodeNum else { return false }
		operation.pendingPacketIDs.insert(packetID)
		operations[operationID] = operation
		return true
	}

	func resolveAdminResponse(packetID: UInt32, sourceNodeNum: Int64) -> UUID? {
		guard let operation = operations.values.first(where: {
			$0.pendingPacketIDs.contains(packetID) && $0.targetNodeNum == sourceNodeNum && !$0.isFinished
		}) else { return nil }
		let result: RemoteAdminConfigOperationResult = operation.kind == .action ? .acknowledged : .succeeded
		return resolvePacket(packetID: packetID, operationID: operation.id, result: result)
	}

	func resolveRouting(packetID: UInt32, sourceNodeNum: Int64, reason: String?, isFailure: Bool) -> UUID? {
		guard let operation = operations.values.first(where: { $0.pendingPacketIDs.contains(packetID) && !$0.isFinished }) else { return nil }
		guard isFailure || (operation.kind == .save && operation.targetNodeNum == sourceNodeNum) else { return nil }
		// A routing ACK only proves that the mesh accepted the packet for delivery. It does not
		// prove that the target executed a destructive action. Keep action packets pending until
		// an admin response (or another target-specific evidence packet) resolves them; timeout
		// then reports `.unconfirmed`.
		let result: RemoteAdminConfigOperationResult = isFailure ? .failed(reason ?? "Remote delivery failed") : .succeeded
		return resolvePacket(packetID: packetID, operationID: operation.id, result: result)
	}

	private func resolvePacket(packetID: UInt32, operationID: UUID, result: RemoteAdminConfigOperationResult) -> UUID {
		guard var operation = operations[operationID], !operation.isFinished else { return operationID }
		operation.pendingPacketIDs.remove(packetID)
		if case .failed = result { operation.result = result }
		if case .acknowledged = result { operation.result = result }
		operations[operationID] = operation
		return operationID
	}

	func waitForPacket(packetID: UInt32, operationID: UUID, timeout: Duration = .seconds(30)) async -> RemoteAdminConfigOperationResult {
		let deadline = ContinuousClock.now + timeout
		while !Task.isCancelled {
			guard let operation = operations[operationID] else { return .failed("Operation cancelled") }
			if let result = operation.result { return result }
			if !operation.pendingPacketIDs.contains(packetID) {
				return operation.kind == .action ? .acknowledged : .succeeded
			}
			if ContinuousClock.now >= deadline {
				self.timeout(operationID)
				return operation.kind == .action ? .unconfirmed : .timedOut
			}
			try? await Task.sleep(for: .milliseconds(50))
		}
		fail(operationID, with: "Operation cancelled")
		return .failed("Operation cancelled")
	}

	func timeout(_ operationID: UUID) {
		guard var operation = operations[operationID], !operation.isFinished else { return }
		operation.pendingPacketIDs.removeAll()
		operation.result = operation.kind == .action ? .unconfirmed : .timedOut
		operations[operationID] = operation
	}

	func finish(_ operationID: UUID) -> RemoteAdminConfigOperationResult {
		guard var operation = operations[operationID], !operation.isFinished else { return operations[operationID]?.result ?? .failed("Operation cancelled") }
		guard operation.pendingPacketIDs.isEmpty else { return operation.kind == .action ? .unconfirmed : .timedOut }
		operation.result = operation.kind == .action ? .acknowledged : .succeeded
		operations[operationID] = operation
		return operation.result ?? .failed("Operation cancelled")
	}

	func fail(_ operationID: UUID, with error: Error) {
		fail(operationID, with: error.localizedDescription)
	}

	func fail(_ operationID: UUID, with message: String) {
		guard var operation = operations[operationID], !operation.isFinished else { return }
		operation.pendingPacketIDs.removeAll()
		operation.result = .failed(message)
		operations[operationID] = operation
	}

	func failAll(with message: String) {
		for operationID in Array(operations.keys) { fail(operationID, with: message) }
	}

	func latest(for targetNodeNum: Int64, kind: RemoteAdminConfigOperationKind, section: String) -> RemoteAdminConfigOperation? {
		operations.values.filter { $0.targetNodeNum == targetNodeNum && $0.kind == kind && $0.section == section }.max { $0.sequence < $1.sequence }
	}
}
