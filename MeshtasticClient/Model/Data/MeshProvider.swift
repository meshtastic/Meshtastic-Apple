/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class to fetch data from the remote server and save it to the Core Data store.
*/

import CoreData
import OSLog

class MeshProvider {

	// MARK: Logging

	let logger = Logger(subsystem: "com.example.apple-samplecode.Earthquakes", category: "persistence")

	// MARK: Core Data

	/// A shared quakes provider for use within the main app bundle.
	static let shared = MeshProvider()

	/// A quakes provider for use with canvas previews.
	static let preview: MeshProvider = {
		let provider = MeshProvider(inMemory: true)
		//MessageEntity.makePreviews(count: 10)
		return provider
	}()

	private let inMemory: Bool
	private var notificationToken: NSObjectProtocol?

	private init(inMemory: Bool = false) {
		self.inMemory = inMemory

		// Observe Core Data remote change notifications on the queue where the changes were made.
		notificationToken = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { note in
			self.logger.debug("Received a persistent store remote change notification.")
			Task {
				await self.fetchPersistentHistory()
			}
		}
	}

	deinit {
		if let observer = notificationToken {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	/// A peristent history token used for fetching transactions from the store.
	private var lastToken: NSPersistentHistoryToken?

	/// A persistent container to set up the Core Data stack.
	lazy var container: NSPersistentContainer = {
		/// - Tag: persistentContainer
		let container = NSPersistentContainer(name: "Mesh")

		guard let description = container.persistentStoreDescriptions.first else {
			fatalError("Failed to retrieve a persistent store description.")
		}

		if inMemory {
			description.url = URL(fileURLWithPath: "/dev/null")
		}

		// Enable persistent store remote change notifications
		/// - Tag: persistentStoreRemoteChange
		description.setOption(true as NSNumber,
							  forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

		// Enable persistent history tracking
		/// - Tag: persistentHistoryTracking
		description.setOption(true as NSNumber,
							  forKey: NSPersistentHistoryTrackingKey)

		container.loadPersistentStores { storeDescription, error in
			if let error = error as NSError? {
				fatalError("Unresolved error \(error), \(error.userInfo)")
			}
		}

		// This sample refreshes UI by consuming store changes via persistent history tracking.
		/// - Tag: viewContextMergeParentChanges
		container.viewContext.automaticallyMergesChangesFromParent = false
		container.viewContext.name = "viewContext"
		/// - Tag: viewContextMergePolicy
		container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		container.viewContext.undoManager = nil
		container.viewContext.shouldDeleteInaccessibleFaults = true
		return container
	}()

	/// Creates and configures a private queue context.
	private func newTaskContext() -> NSManagedObjectContext {
		// Create a private queue context.
		/// - Tag: newBackgroundContext
		let taskContext = container.newBackgroundContext()
		taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		// Set unused undoManager to nil for macOS (it is nil by default on iOS)
		// to reduce resource requirements.
		taskContext.undoManager = nil
		return taskContext
	}

	/// Uses `NSBatchInsertRequest` (BIR) to import a JSON dictionary into the Core Data store on a private queue.
	func importMessages(from propertiesList: [MessageProperties]) async throws {
		guard !propertiesList.isEmpty else { return }

		let taskContext = newTaskContext()
		// Add name and author to identify source of persistent history changes.
		taskContext.name = "importContext"
		taskContext.transactionAuthor = "importMessages"

		/// - Tag: performAndWait
		try await taskContext.perform {
			// Execute the batch insert.
			/// - Tag: batchInsertRequest
			let batchInsertRequest = self.newBatchInsertRequest(with: propertiesList)
			if let fetchResult = try? taskContext.execute(batchInsertRequest),
			   let batchInsertResult = fetchResult as? NSBatchInsertResult,
			   let success = batchInsertResult.result as? Bool, success {
				return
			}
			self.logger.debug("Failed to execute batch insert request.")
			throw MeshDataError.batchInsertError
		}

		logger.debug("Successfully inserted data.")
	}

	private func newBatchInsertRequest(with propertyList: [MessageProperties]) -> NSBatchInsertRequest {
		var index = 0
		let total = propertyList.count

		// Provide one dictionary at a time when the closure is called.
		let batchInsertRequest = NSBatchInsertRequest(entity: MessageEntity.entity(), dictionaryHandler: { dictionary in
			guard index < total else { return true }
			dictionary.addEntries(from: propertyList[index].dictionaryValue)
			index += 1
			return false
		})
		return batchInsertRequest
	}

	/// Synchronously deletes given records in the Core Data store with the specified object IDs.
	func deleteQuakes(identifiedBy objectIDs: [NSManagedObjectID]) {
		let viewContext = container.viewContext
		logger.debug("Start deleting data from the store...")

		viewContext.perform {
			objectIDs.forEach { objectID in
				let quake = viewContext.object(with: objectID)
				viewContext.delete(quake)
			}
		}

		logger.debug("Successfully deleted data.")
	}

	/// Asynchronously deletes records in the Core Data store with the specified `Quake` managed objects.
	func deleteMessages(_ messages: [MessageEntity]) async throws {
		let objectIDs = messages.map { $0.objectID }
		let taskContext = newTaskContext()
		// Add name and author to identify source of persistent history changes.
		taskContext.name = "deleteContext"
		taskContext.transactionAuthor = "deleteMessages"
		logger.debug("Start deleting data from the store...")

		try await taskContext.perform {
			// Execute the batch delete.
			let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDs)
			guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
				  let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
				  let success = batchDeleteResult.result as? Bool, success
			else {
				self.logger.debug("Failed to execute batch delete request.")
				throw MeshDataError.batchDeleteError
			}
		}

		logger.debug("Successfully deleted data.")
	}

	func fetchPersistentHistory() async {
		do {
			try await fetchPersistentHistoryTransactionsAndChanges()
		} catch {
			logger.debug("\(error.localizedDescription)")
		}
	}

	private func fetchPersistentHistoryTransactionsAndChanges() async throws {
		let taskContext = newTaskContext()
		taskContext.name = "persistentHistoryContext"
		logger.debug("Start fetching persistent history changes from the store...")

		try await taskContext.perform {
			// Execute the persistent history change since the last transaction.
			/// - Tag: fetchHistory
			let changeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastToken)
			let historyResult = try taskContext.execute(changeRequest) as? NSPersistentHistoryResult
			if let history = historyResult?.result as? [NSPersistentHistoryTransaction],
			   !history.isEmpty {
				self.mergePersistentHistoryChanges(from: history)
				return
			}

			self.logger.debug("No persistent history transactions found.")
			throw MeshDataError.persistentHistoryChangeError
		}

		logger.debug("Finished merging history changes.")
	}

	private func mergePersistentHistoryChanges(from history: [NSPersistentHistoryTransaction]) {
		self.logger.debug("Received \(history.count) persistent history transactions.")
		// Update view context with objectIDs from history change request.
		/// - Tag: mergeChanges
		let viewContext = container.viewContext
		viewContext.perform {
			for transaction in history {
				viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
				self.lastToken = transaction.token
			}
		}
	}
}
