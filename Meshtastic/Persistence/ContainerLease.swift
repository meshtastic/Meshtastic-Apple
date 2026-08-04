// ContainerLease.swift
// Meshtastic

import Foundation

/// Identifies one live persistence-container generation and its concrete container instance.
struct ContainerLease: Equatable, Sendable {
	fileprivate let generation: UInt64
	fileprivate let containerID: ObjectIdentifier
}

enum ContainerLeaseError: Error, Equatable {
	case stale
	case transitioning
	case drainTimedOut
	case invalidTransition
}

struct ContainerTransition: Equatable, Sendable {
	fileprivate let id: UUID
}

/// Captures a container, its lease, and the coordinator that issued both.
/// Writers retain this value with their `ModelContext` instead of reacquiring the current lease.
struct ContainerWriteAccess: Sendable {
	private let coordinator: ContainerAccessCoordinator
	private let lease: ContainerLease
	private let containerID: ObjectIdentifier

	init(
		coordinator: ContainerAccessCoordinator,
		lease: ContainerLease,
		containerID: ObjectIdentifier
	) {
		self.coordinator = coordinator
		self.lease = lease
		self.containerID = containerID
	}

	func beginWrite() throws -> ContainerWritePermit {
		try beginWrite(containerID: containerID)
	}

	func beginWrite(containerID writerContainerID: ObjectIdentifier) throws -> ContainerWritePermit {
		guard writerContainerID == containerID else { throw ContainerLeaseError.stale }
		return try coordinator.beginWrite(using: lease, containerID: writerContainerID)
	}
}

/// A synchronous permit held from the last lease check through `ModelContext.save()`.
/// Releasing the permit lets a waiting container transition continue.
final class ContainerWritePermit: @unchecked Sendable {
	private let lock = NSLock()
	private var finishAction: (() -> Void)?

	fileprivate init(finish: @escaping () -> Void) {
		finishAction = finish
	}

	func finish() {
		lock.lock()
		let action = finishAction
		finishAction = nil
		lock.unlock()
		action?()
	}

	deinit {
		finish()
	}
}

/// Serializes persistence writes against container replacement without blocking the main actor.
///
/// Writers acquire a permit with the lease and container they captured together. A transition
/// rejects new permits, waits for existing permits to finish, then rotates the lease only after
/// the caller has installed the replacement container.
final class ContainerAccessCoordinator: @unchecked Sendable {
	private struct TransitionState {
		let token: ContainerTransition
		var drainContinuation: CheckedContinuation<ContainerTransition, any Error>?
	}

	private let lock = NSLock()
	private var generation: UInt64 = 0
	private var containerID: ObjectIdentifier
	private var activeWriteCount = 0
	private var transition: TransitionState?

	init(containerID: ObjectIdentifier) {
		self.containerID = containerID
	}

	var currentLease: ContainerLease {
		lock.lock()
		let lease = currentLeaseLocked
		lock.unlock()
		return lease
	}

	func requireCurrent(_ lease: ContainerLease) throws {
		lock.lock()
		let isCurrent = lease == currentLeaseLocked
		lock.unlock()
		guard isCurrent else { throw ContainerLeaseError.stale }
	}

	func beginWrite(
		using lease: ContainerLease,
		containerID writerContainerID: ObjectIdentifier
	) throws -> ContainerWritePermit {
		lock.lock()
		guard transition == nil else {
			lock.unlock()
			throw ContainerLeaseError.transitioning
		}
		guard lease == currentLeaseLocked, writerContainerID == containerID else {
			lock.unlock()
			throw ContainerLeaseError.stale
		}
		activeWriteCount += 1
		lock.unlock()

		return ContainerWritePermit { [weak self] in
			self?.finishWrite()
		}
	}

	func beginTransition(timeout: Duration) async throws -> ContainerTransition {
		let token = ContainerTransition(id: UUID())
		return try await withCheckedThrowingContinuation { continuation in
			lock.lock()
			guard transition == nil else {
				lock.unlock()
				continuation.resume(throwing: ContainerLeaseError.transitioning)
				return
			}

			if activeWriteCount == 0 {
				transition = TransitionState(token: token, drainContinuation: nil)
				lock.unlock()
				continuation.resume(returning: token)
				return
			}

			transition = TransitionState(token: token, drainContinuation: continuation)
			lock.unlock()

			Task.detached { [weak self] in
				try? await Task.sleep(for: timeout)
				self?.timeoutTransition(token)
			}
		}
	}

	func commitTransition(
		_ token: ContainerTransition,
		newContainerID: ObjectIdentifier
	) throws {
		lock.lock()
		guard let state = transition,
		      state.token == token,
		      state.drainContinuation == nil,
		      activeWriteCount == 0 else {
			lock.unlock()
			throw ContainerLeaseError.invalidTransition
		}
		generation &+= 1
		containerID = newContainerID
		transition = nil
		lock.unlock()
	}

	func cancelTransition(_ token: ContainerTransition) throws {
		lock.lock()
		guard let state = transition,
		      state.token == token,
		      state.drainContinuation == nil else {
			lock.unlock()
			throw ContainerLeaseError.invalidTransition
		}
		transition = nil
		lock.unlock()
	}

	private var currentLeaseLocked: ContainerLease {
		ContainerLease(generation: generation, containerID: containerID)
	}

	private func finishWrite() {
		var continuation: CheckedContinuation<ContainerTransition, any Error>?
		var token: ContainerTransition?

		lock.lock()
		precondition(activeWriteCount > 0, "Container write permit finished more than once")
		activeWriteCount -= 1
		if activeWriteCount == 0,
		   var state = transition,
		   let waiting = state.drainContinuation {
			state.drainContinuation = nil
			transition = state
			continuation = waiting
			token = state.token
		}
		lock.unlock()

		if let continuation, let token {
			continuation.resume(returning: token)
		}
	}

	private func timeoutTransition(_ token: ContainerTransition) {
		var continuation: CheckedContinuation<ContainerTransition, any Error>?

		lock.lock()
		if let state = transition,
		   state.token == token,
		   let waiting = state.drainContinuation {
			transition = nil
			continuation = waiting
		}
		lock.unlock()

		continuation?.resume(throwing: ContainerLeaseError.drainTimedOut)
	}
}
