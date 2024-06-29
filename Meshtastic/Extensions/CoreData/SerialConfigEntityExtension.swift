import CoreData
import MeshtasticProtobufs

extension SerialConfigEntity {
	convenience init(
		context: NSManagedObjectContext,
		config: ModuleConfig.SerialConfig
	) {
		self.init(context: context)
		self.enabled = config.enabled
		self.echo = config.echo
		self.rxd = Int32(config.rxd)
		self.txd = Int32(config.txd)
		self.baudRate = Int32(config.baud.rawValue)
		self.timeout = Int32(config.timeout)
		self.mode = Int32(config.mode.rawValue)
	}

	func update(with config: ModuleConfig.SerialConfig) {
		enabled = config.enabled
		echo = config.echo
		rxd = Int32(config.rxd)
		txd = Int32(config.txd)
		baudRate = Int32(config.baud.rawValue)
		timeout = Int32(config.timeout)
		mode = Int32(config.mode.rawValue)
	}
}
