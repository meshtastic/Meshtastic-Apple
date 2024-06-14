//
//  NSPersistentContainer.swift
//
//  Created by Tom Harrington on 5/12/20.
//  Copyright © 2020 Atomic Bird LLC. All rights reserved.
//  Gist from https://atomicbird.com/blog/core-data-back-up-store/
//

import Foundation
import CoreData

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
	func restorePersistentStore(from backupURL: URL) throws -> Void {
		guard backupURL.isFileURL else {
			throw CopyPersistentStoreErrors.invalidSource("Backup URL must be a file URL")
		}
		
		for persistentStoreDescription in persistentStoreDescriptions {
			guard let loadedStoreURL = persistentStoreDescription.url else {
				continue
			}
			guard FileManager.default.fileExists(atPath: backupURL.path) else {
				throw CopyPersistentStoreErrors.invalidSource("Missing backup store for \(backupURL)")
			}
			do {
				let storeOptions = persistentStoreDescription.options
				let configurationName = persistentStoreDescription.configuration
				let storeType = persistentStoreDescription.type
				
				// Replace the current store with the backup copy. This has a side effect of removing the current store from the Core Data stack.
				// When restoring, it's necessary to use the current persistent store coordinator.
				try persistentStoreCoordinator.replacePersistentStore(at: loadedStoreURL, destinationOptions: storeOptions, withPersistentStoreFrom: backupURL, sourceOptions: storeOptions, ofType: storeType)
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
	func copyPersistentStores(to destinationURL: URL, overwriting: Bool = false) throws -> Void {
		print(destinationURL)
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
			let temporaryPSC = NSPersistentStoreCoordinator(managedObjectModel: persistentStoreCoordinator.managedObjectModel)
			let destinationStoreURL = destinationURL.appendingPathComponent(storeURL.lastPathComponent)
			
			if !overwriting && FileManager.default.fileExists(atPath: destinationStoreURL.path) {
				// If the destination exists, the migratePersistentStore call will update it in place. That's fine unless we're not overwriting.
				throw CopyPersistentStoreErrors.destinationError("Destination already exists at \(destinationStoreURL)")
			}
			do {
				let newStore = try temporaryPSC.addPersistentStore(ofType: persistentStoreDescription.type, configurationName: persistentStoreDescription.configuration, at: persistentStoreDescription.url, options: persistentStoreDescription.options)
				let _ = try temporaryPSC.migratePersistentStore(newStore, to: destinationStoreURL, options: persistentStoreDescription.options, withType: persistentStoreDescription.type)
			} catch {
				throw CopyPersistentStoreErrors.copyStoreError("\(error.localizedDescription)")
			}
		}
	}
}
