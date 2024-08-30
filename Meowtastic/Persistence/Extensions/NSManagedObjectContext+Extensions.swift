import CoreData

extension NSManagedObjectContext {
	public func executeAndMergeChanges(using batchDeleteRequest: NSBatchDeleteRequest) throws {
		batchDeleteRequest.resultType = .resultTypeObjectIDs

		let result = try execute(batchDeleteRequest) as? NSBatchDeleteResult
		let changes = [
			NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []
		]

		NSManagedObjectContext.mergeChanges(
			fromRemoteContextSave: changes,
			into: [self]
		)
	}
}
