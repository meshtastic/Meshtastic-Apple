import CoreData

class CoreDataTools {
	let debounce = Debounce<() async -> Void>(duration: .milliseconds(175)) { action in
		await action()
	}

	private let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)

	@discardableResult
	func saveData() async -> Bool {
		privateContext.performAndWait { [weak self] in
			guard
				let self,
				privateContext.hasChanges
			else {
				return false
			}

			do {
				try privateContext.save()

				return true
			}
			catch {
				privateContext.rollback()

				return false
			}
		}
	}
}
