import CoreData
import OSLog

final class Persistence {
	static let shared = Persistence()

	static var preview: Persistence = {
		let result = Persistence(inMemory: false)
		let context = result.container.viewContext

		for _ in 0..<10 {
			let newItem = NodeInfoEntity(context: context)
			newItem.lastHeard = Date()
		}

		try? context.save()

		return result
	}()

	let container: NSPersistentContainer

	init(inMemory: Bool = false) {
		container = NSPersistentContainer(name: "Meowtastic")

		if inMemory {
			container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
		}

		container.loadPersistentStores { [weak self] _, error in
			guard let self else {
				return
			}

			// Merge policy that favors in memory data over data in the db
			self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
			self.container.viewContext.automaticallyMergesChangesFromParent = true

			if let error = error as NSError? {
				Logger.data.error("CoreData Error: \(error.localizedDescription). Now attempting to truncate CoreData database.  All app data will be lost.")

				self.clearDatabase()
			}
		}
	}

	func clearDatabase() {
		guard let url = container.persistentStoreDescriptions.first?.url else {
			return
		}

		let coordinator = container.persistentStoreCoordinator

		do {
			try coordinator.destroyPersistentStore(
				at: url,
				ofType: NSSQLiteStoreType,
				options: nil
			)


			do {
				try coordinator.addPersistentStore(
					ofType: NSSQLiteStoreType,
					configurationName: nil,
					at: url,
					options: nil
				)
			}
			catch let error {
				Logger.data.error("Failed to re-create CoreData database: \(error.localizedDescription)")
			}
		}
		catch let error {
			Logger.data.error("Failed to destroy CoreData database, delete the app and re-install to clear data. Attempted to clear persistent store: \(error.localizedDescription)")
		}
	}
}
