import Foundation
import CoreData

extension NodeInfoEntity {
	@nonobjc public class func createFetchRequest() -> NSFetchRequest<NodeInfoEntity> {
		return NSFetchRequest<Commit>(entityName: "NodeInfoEntity")
	}

	
	@NSManaged public var id: UInt32
	@NSManaged public var num: UInt32
	@NSManaged public var sha: String
	@NSManaged public var url: String
	
	
}
