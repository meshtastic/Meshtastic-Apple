//
//  AsyncGate.swift
//  Meshtastic
//
//  Created by Jake on 8/20/25.
//

import Foundation

actor AsyncGate {
	private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
	private var isOpen = false

	/// Wait until the gate is opened. Respects cancellation.
	func wait() async throws {
		if isOpen { return }

		let id = UUID()

		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
				waiters[id] = cont
			}
		} onCancel: {
			Task { [weak self] in
				await self?.cancelWaiter(id: id)
			}
		}
	}

	/// Opens the gate, resuming all current waiters.
	func open() {
		isOpen = true
		for (_, cont) in waiters {
			cont.resume()
		}
		waiters.removeAll()
	}

	/// Cancels all current waiters with `CancellationError`.
	func cancelAll() {
		for (_, cont) in waiters {
			cont.resume(throwing: CancellationError())
		}
		waiters.removeAll()
	}

	/// Resets the gate back to closed.
	/// Future waiters will suspend again until `open()` is called.
	func reset() {
		isOpen = false
	}

	private func cancelWaiter(id: UUID) {
		if let cont = waiters.removeValue(forKey: id) {
			cont.resume(throwing: CancellationError())
		}
	}
}
