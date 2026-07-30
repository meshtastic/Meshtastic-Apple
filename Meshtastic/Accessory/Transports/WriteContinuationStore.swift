//
//  WriteContinuationStore.swift
//  Meshtastic
//
//  Keyed storage for write continuations, used by BLEConnection to avoid the double-resume
//  hazard between didWriteValueFor (CoreBluetooth callback) and the withTaskCancellationHandler
//  onCancel path. Each write is registered under a unique UUID; whichever side (callback or
//  cancel) removes the entry first wins, and the other sees nil and no-ops.
//
//  Not an actor: the store lives inside an actor-isolated property (BLEConnection is an actor),
//  so all access is already serialized.
//

import Foundation

struct WriteContinuationStore {
	/// FIFO-ordered entries. An array of tuples preserves insertion order so didWriteValueFor
	/// can consume the oldest entry (CoreBluetooth delivers callbacks in write order), while
	/// the cancel handler targets a specific UUID.
	private var entries: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

	var isEmpty: Bool { entries.isEmpty }

	/// Register a continuation under a unique ID. Called inside withCheckedThrowingContinuation.
	mutating func insert(id: UUID, continuation: CheckedContinuation<Void, Error>) {
		entries.append((id, continuation))
	}

	/// Remove and return the continuation for a specific ID (cancel path).
	/// Returns nil if didWriteValueFor already consumed it.
	mutating func remove(id: UUID) -> CheckedContinuation<Void, Error>? {
		guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
		return entries.remove(at: index).continuation
	}

	/// Remove and return the oldest entry (didWriteValueFor path — CoreBluetooth delivers
	/// callbacks in write order). Returns nil if the cancel handler already consumed it.
	mutating func removeFirst() -> (id: UUID, continuation: CheckedContinuation<Void, Error>)? {
		guard !entries.isEmpty else { return nil }
		return entries.removeFirst()
	}

	/// Resume every pending continuation with an error and clear the store.
	/// Used during disconnect teardown.
	mutating func drainAll(throwing error: Error) {
		for entry in entries {
			entry.continuation.resume(throwing: error)
		}
		entries.removeAll()
	}
}
