//
//  Persistence.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import CoreData
import OSLog

class PersistenceController {

	static let shared = PersistenceController()

	static var preview: PersistenceController = {
		let result = PersistenceController(inMemory: false)
		let viewContext = result.container.viewContext
		for _ in 0..<10 {
			let newItem = NodeInfoEntity(context: viewContext)
			newItem.lastHeard = Date()
		}
		do {
			try viewContext.save()
		} catch {
			// Replace this implementation with code to handle the error appropriately.
			// fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
			let nsError = error as NSError
			fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
		}
		return result
	}()

	let container: NSPersistentContainer

	init(inMemory: Bool = false) {

		container = NSPersistentContainer(name: "Meshtastic")

		if inMemory {
			container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
		}

		container.loadPersistentStores(completionHandler: { (_, error) in

			// Merge policy that favors in memory data over data in the db
			self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
			self.container.viewContext.automaticallyMergesChangesFromParent = true
			self.container.viewContext.retainsRegisteredObjects = true

			if let error = error as NSError? {

				Logger.data.error("CoreData Error: \(error.localizedDescription, privacy: .public). Now attempting to truncate CoreData database.  All app data will be lost.")
				self.clearDatabase()
			}
		})
	}

	public func clearDatabase() {
		guard let url = self.container.persistentStoreDescriptions.first?.url else { return }

		let persistentStoreCoordinator = self.container.persistentStoreCoordinator
		 do {
			 try persistentStoreCoordinator.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
			 Logger.data.error("CoreData database truncated.  All app data has been erased.")

			 do {
				 try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
			 } catch let error {
				 Logger.data.error("Failed to re-create CoreData database: \(error.localizedDescription, privacy: .public)")
			 }

		} catch let error {
			Logger.data.error("Failed to destroy CoreData database, delete the app and re-install to clear data. Attempted to clear persistent store: \(error.localizedDescription, privacy: .public)")
		}
	}
}

extension NSManagedObjectContext {

	/// Executes the given `NSBatchDeleteRequest` and directly merges the changes to bring the given managed object context up to date.
	///
	/// - Parameter batchDeleteRequest: The `NSBatchDeleteRequest` to execute.
	/// - Throws: An error if anything went wrong executing the batch deletion.
	public func executeAndMergeChanges(using batchDeleteRequest: NSBatchDeleteRequest) throws {
		batchDeleteRequest.resultType = .resultTypeObjectIDs

		let result = try execute(batchDeleteRequest) as? NSBatchDeleteResult
		let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]

		NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
	}
}

//  Created by Tom Harrington on 5/12/20.
//  Copyright © 2020 Atomic Bird LLC. All rights reserved.
//  Gist from https://atomicbird.com/blog/core-data-back-up-store/
//
extension NSPersistentContainer {
	enum CopyPersistentStoreErrors: Error {
		case invalidDestination(String)
		case destinationError(String)
		case destinationNotRemoved(String)
		case copyStoreError(String)
		case invalidSource(String)
	}

}
