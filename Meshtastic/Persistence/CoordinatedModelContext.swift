// CoordinatedModelContext.swift
// Meshtastic

import Foundation
import SwiftData

private final class WeakModelContainer: @unchecked Sendable {
	weak var value: ModelContainer?

	init(_ value: ModelContainer) {
		self.value = value
	}
}

enum ContainerWriteRegistration {
	case unmanaged
	case active(ContainerWriteAccess)
	case retired
}

/// Process-local directory that lets any `ModelContext` find the write authority for its exact
/// container. Entries retain containers weakly and verify object identity during lookup, so a
/// reused `ObjectIdentifier` cannot inherit an old container's active or retired state.
final class ContainerWriteAccessDirectory: @unchecked Sendable {
	static let shared = ContainerWriteAccessDirectory()

	private enum State {
		case active(ContainerWriteAccess)
		case retired
	}

	private struct Entry {
		let container: WeakModelContainer
		var state: State
	}

	private let lock = NSLock()
	private var entries: [ObjectIdentifier: Entry] = [:]

	private init() {}

	func register(_ container: ModelContainer, access: ContainerWriteAccess) {
		let identifier = ObjectIdentifier(container)
		lock.lock()
		entries[identifier] = Entry(container: WeakModelContainer(container), state: .active(access))
		lock.unlock()
	}

	func retire(_ container: ModelContainer) {
		let identifier = ObjectIdentifier(container)
		lock.lock()
		if let entry = entries[identifier], entry.container.value === container {
			entries[identifier] = Entry(container: entry.container, state: .retired)
		}
		lock.unlock()
	}

	func registration(for container: ModelContainer) -> ContainerWriteRegistration {
		let identifier = ObjectIdentifier(container)
		lock.lock()
		guard let entry = entries[identifier] else {
			lock.unlock()
			return .unmanaged
		}
		guard let registeredContainer = entry.container.value else {
			entries.removeValue(forKey: identifier)
			lock.unlock()
			return .unmanaged
		}
		guard registeredContainer === container else {
			entries.removeValue(forKey: identifier)
			lock.unlock()
			return .unmanaged
		}
		let state = entry.state
		lock.unlock()

		switch state {
		case .active(let access):
			return .active(access)
		case .retired:
			return .retired
		}
	}
}

extension ModelContext {
	/// Saves through the owning container's write coordinator when the context belongs to a
	/// `PersistenceController`. Independent test and preview containers remain unmanaged.
	func coordinatedSave() throws {
		switch ContainerWriteAccessDirectory.shared.registration(for: container) {
		case .unmanaged:
			try save()
		case .retired:
			// The retired container may already be deallocated. Touching this context again,
			// including rollback(), can trap inside SwiftData instead of returning an error.
			throw ContainerLeaseError.stale
		case .active(let access):
			let permit: ContainerWritePermit
			do {
				permit = try access.beginWrite(containerID: ObjectIdentifier(container))
			} catch {
				if error as? ContainerLeaseError == .transitioning {
					rollback()
				}
				throw error
			}
			defer { permit.finish() }
			try save()
		}
	}
}
