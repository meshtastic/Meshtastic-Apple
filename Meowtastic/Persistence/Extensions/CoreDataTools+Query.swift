import CoreData

extension CoreDataTools {
	public func getNodeInfo(id: Int64, context: NSManagedObjectContext) -> NodeInfoEntity? {
		let request = NodeInfoEntity.fetchRequest()
		request.predicate = NSPredicate(format: "num == %lld", Int64(id))

		if let nodes = try? context.fetch(request), nodes.count == 1 {
			return nodes[0]
		}

		return nil
	}

	public func getStoreAndForwardMessageIds(seconds: Int, context: NSManagedObjectContext) -> [UInt32] {
		let time = seconds * -1
		let timeRange = Calendar.current.date(byAdding: .minute, value: time, to: Date())
		let milleseconds = Int32(timeRange?.timeIntervalSince1970 ?? 0)

		let request = MessageEntity.fetchRequest()
		request.predicate = NSPredicate(format: "messageTimestamp >= %d", milleseconds)

		if let messages = try? context.fetch(request), messages.count == 1 {
			return messages.map { message in
				UInt32(message.messageId)
			}
		}

		return []
	}

	public func getTraceRoute(id: Int64, context: NSManagedObjectContext) -> TraceRouteEntity? {
		let request = TraceRouteEntity.fetchRequest()
		request.predicate = NSPredicate(format: "id == %lld", Int64(id))

		if let traceRoutes = try? context.fetch(request), traceRoutes.count == 1 {
			return traceRoutes[0]
		}

		return nil
	}

	public func getUser(id: Int64, context: NSManagedObjectContext) -> UserEntity {
		let request = UserEntity.fetchRequest()
		request.predicate = NSPredicate(format: "num == %lld", Int64(id))

		if let users = try?  context.fetch(request), users.count == 1 {
			return users[0]
		}

		return UserEntity(context: context)
	}
}
