import Foundation

final class SafeStorage<T>: @unchecked Sendable {
	private let lock = NSRecursiveLock()
	private var stored: T

	init(stored: T) {
		self.stored = stored
	}

	func get() -> T {
		self.lock.lock()
		defer { self.lock.unlock() }
		return self.stored
	}

	func set(stored: T) {
		self.lock.lock()
		defer { self.lock.unlock() }
		self.stored = stored
	}

	func apply<R>(block: (inout T) -> R) -> R {
		self.lock.lock()
		defer { self.lock.unlock() }
		return block(&self.stored)
	}
}
