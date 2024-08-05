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

			if let error = error as NSError? {

				Logger.data.error("CoreData Error: \(error.localizedDescription). Now attempting to truncate CoreData database.  All app data will be lost.")
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
				 Logger.data.error("Failed to re-create CoreData database: \(error.localizedDescription)")
			 }

		} catch let error {
			Logger.data.error("Failed to destroy CoreData database, delete the app and re-install to clear data. Attempted to clear persistent store: \(error.localizedDescription)")
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

	/// Restore backup persistent stores located in the directory referenced by `backupURL`.
	 ///
	 /// **Be very careful with this**. To restore a persistent store, the current persistent store must be removed from the container. When that happens, **all currently loaded Core Data objects** will become invalid. Using them after restoring will cause your app to crash. When calling this method you **must** ensure that you do not continue to use any previously fetched managed objects or existing fetched results controllers. **If this method does not throw, that does not mean your app is safe.** You need to take extra steps to prevent crashes. The details vary depending on the nature of your app.
	 /// - Parameter backupURL: A file URL containing backup copies of all currently loaded persistent stores.
	 /// - Throws: `CopyPersistentStoreError` in various situations.
	 /// - Returns: Nothing. If no errors are thrown, the restore is complete.
	 func restorePersistentStore(from backupURL: URL) throws {
		 guard backupURL.isFileURL else {
			 throw CopyPersistentStoreErrors.invalidSource("Backup URL must be a file URL")
		 }

		 var isDirectory: ObjCBool = false
		 if FileManager.default.fileExists(atPath: backupURL.path, isDirectory: &isDirectory) {
			 if !isDirectory.boolValue {
				 throw CopyPersistentStoreErrors.invalidSource("Source URL must be a directory")
			 }
		 } else {
			 throw CopyPersistentStoreErrors.invalidSource("Source URL must exist")
		 }

		 for persistentStoreDescription in persistentStoreDescriptions {
			 guard let loadedStoreURL = persistentStoreDescription.url else {
				 continue
			 }
			 let backupStoreURL = backupURL.appendingPathComponent(loadedStoreURL.lastPathComponent)
			 guard FileManager.default.fileExists(atPath: backupStoreURL.path) else {
				 throw CopyPersistentStoreErrors.invalidSource("Missing backup store for \(backupStoreURL)")
			 }
			 do {
				 let storeOptions = persistentStoreDescription.options
				 let configurationName = persistentStoreDescription.configuration
				 let storeType = persistentStoreDescription.type
				 // Replace the current store with the backup copy. This has a side effect of removing the current store from the Core Data stack.
				 // When restoring, it's necessary to use the current persistent store coordinator.
				 try persistentStoreCoordinator.replacePersistentStore(at: loadedStoreURL, destinationOptions: storeOptions, withPersistentStoreFrom: backupStoreURL, sourceOptions: storeOptions, ofType: storeType)
				 // Add the persistent store at the same location we've been using, because it was removed in the previous step.
				 try persistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: configurationName, at: loadedStoreURL, options: storeOptions)
			 } catch {
				 throw CopyPersistentStoreErrors.copyStoreError("Could not restore: \(error.localizedDescription)")
			 }
		 }
	 }

	/// Copy all loaded persistent stores to a new directory. Each currently loaded file-based persistent store will be copied (including journal files, external binary storage, and anything else Core Data needs) into the destination directory to a persistent store with the same name and type as the existing store. In-memory stores, if any, are skipped.
	/// - Parameters:
	///   - destinationURL: Destination for new persistent store files. Must be a file URL. If `overwriting` is `false` and `destinationURL` exists, it must be a directory.
	///   - overwriting: If `true`, any existing copies of the persistent store will be replaced or updated. If `false`, existing copies will not be changed or remoted. When this is `false`, the destination persistent store file must not already exist.
	/// - Throws: `CopyPersistentStoreError`
	/// - Returns: Nothing. If no errors are thrown, all loaded persistent stores will be copied to the destination directory.
	func copyPersistentStores(to destinationURL: URL, overwriting: Bool = false) throws {

		guard !destinationURL.relativeString.contains("/0/") else {
			throw CopyPersistentStoreErrors.invalidDestination("Invalid 0 Node Id")
		}

		guard destinationURL.isFileURL else {
			throw CopyPersistentStoreErrors.invalidDestination("Destination URL must be a file URL")
		}
		// If the destination exists and we aren't overwriting it, then it must be a directory. (If we are overwriting, we'll remove it anyway, so it doesn't matter whether it's a directory).
		var isDirectory: ObjCBool = false
		if !overwriting && FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) {
			if !isDirectory.boolValue {
				throw CopyPersistentStoreErrors.invalidDestination("Destination URL must be a directory")
			}
			// Don't check if destination stores exist in the destination dir, that comes later on a per-store basis.
		}
		// If we're overwriting, remove the destination.
		if overwriting && FileManager.default.fileExists(atPath: destinationURL.path) {
			do {
				try FileManager.default.removeItem(at: destinationURL)
			} catch {
				throw CopyPersistentStoreErrors.destinationNotRemoved("Can't overwrite destination at \(destinationURL)")
			}
		}
		// Create the destination directory
		do {
			try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
		} catch {
			throw CopyPersistentStoreErrors.destinationError("Could not create destination directory at \(destinationURL)")
		}

		for persistentStoreDescription in persistentStoreDescriptions {
			guard let storeURL = persistentStoreDescription.url else {
				continue
			}
			guard persistentStoreDescription.type != NSInMemoryStoreType else {
				continue
			}
			let destinationStoreURL = destinationURL.appendingPathComponent(storeURL.lastPathComponent)

			if !overwriting && FileManager.default.fileExists(atPath: destinationStoreURL.path) {
				// If the destination exists, the replacePersistentStore call will update it in place. That's fine unless we're not overwriting.
				throw CopyPersistentStoreErrors.destinationError("Destination already exists at \(destinationStoreURL)")
			}
			do {
				// Replace an existing backup, if any, with a new one with the same options and type. This doesn't affect the current Core Data stack.
				// The function name says "replace", but it works if there's nothing at the destination yet. In that case it creates a new persistent store.
				// Note that for backup, it doesn't matter if the persistent store coordinator is the one currently in use or a different one. It could be a class function, for this use.
				try persistentStoreCoordinator.replacePersistentStore(at: destinationStoreURL, destinationOptions: persistentStoreDescription.options, withPersistentStoreFrom: storeURL, sourceOptions: persistentStoreDescription.options, ofType: persistentStoreDescription.type)
				/// Cleanup extra files
				let directory = destinationStoreURL.deletingLastPathComponent()
				/// Delete -wal file
				do {
					try FileManager.default.removeItem(at: directory.appendingPathComponent("Meshtastic.sqlite-wal"))
					/// Delete -shm file
					do {
						try FileManager.default.removeItem(at: directory.appendingPathComponent("Meshtastic.sqlite-shm"))
					} catch {
						Logger.services.error("🗄 Error Deleting Meshtastic.sqlite-shm file \(error, privacy: .public)")
					}
				} catch {
					Logger.services.error("🗄 Error Deleting Meshtastic.sqlite-wal file \(error, privacy: .public)")
				}
			} catch {
				Logger.services.error("🗄 Error Deleting Meshtastic.sqlite file \(error, privacy: .public)")
				throw CopyPersistentStoreErrors.copyStoreError("\(error.localizedDescription)")
			}
		}
	}
}
