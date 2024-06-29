import CoreData
import MeshtasticProtobufs

extension StoreForwardConfigEntity {
	convenience init(
		context: NSManagedObjectContext,
		config: ModuleConfig.StoreForwardConfig
	) {
		self.init(context: context)
		self.enabled = config.enabled
		self.heartbeat = config.heartbeat
		self.records = Int32(config.records)
		self.historyReturnMax = Int32(config.historyReturnMax)
		self.historyReturnWindow = Int32(config.historyReturnWindow)
	}

	func update(with config: ModuleConfig.StoreForwardConfig) {
		enabled = config.enabled
		heartbeat = config.heartbeat
		records = Int32(config.records)
		historyReturnMax = Int32(config.historyReturnMax)
		historyReturnWindow = Int32(config.historyReturnWindow)
	}
}
