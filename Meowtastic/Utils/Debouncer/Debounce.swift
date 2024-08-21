public final class Debounce<T>: Sendable {
	private let output: @Sendable (T) async -> Void
	private let stateMachine: SafeStorage<StateMachine<T>>
	private let task: SafeStorage<Task<Void, Never>?>

	public init(
		duration: ContinuousClock.Duration,
		output: @Sendable @escaping (T) async -> Void
	) {
		self.stateMachine = SafeStorage(stored: StateMachine(duration: duration))
		self.task = SafeStorage(stored: nil)
		self.output = output
	}

	public func emit(value: T) {
		let (shouldStartATask, dueTime) = self.stateMachine.apply { machine in
			machine.newValue(value)
		}
		
		if shouldStartATask {
			self.task.set(stored: Task { [output, stateMachine] in
				var localDueTime = dueTime
				loop: while true {
					try? await Task.sleep(until: localDueTime, clock: .continuous)

					let action = stateMachine.apply { machine in
						machine.sleepIsOver()
					}

					switch action {
					case .finishDebouncing(let value):
						await output(value)
						break loop
					case .continueDebouncing(let newDueTime):
						localDueTime = newDueTime
						continue loop
					}
				}
			})
		}
	}

	deinit {
		self.task.get()?.cancel()
	}
}
