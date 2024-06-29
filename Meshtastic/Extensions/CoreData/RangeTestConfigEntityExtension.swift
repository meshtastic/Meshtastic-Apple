import CoreData
import MeshtasticProtobufs

extension RangeTestConfigEntity {
	convenience init(
		context: NSManagedObjectContext,
		config: ModuleConfig.RangeTestConfig
	) {
		self.init(context: context)
		self.sender = Int32(config.sender)
		self.enabled = config.enabled
		self.save = config.save
	}

	func update(with config: ModuleConfig.RangeTestConfig) {
		sender = Int32(config.sender)
		enabled = config.enabled
		save = config.save
	}
}
