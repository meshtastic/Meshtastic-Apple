import SwiftData
import MeshtasticProtobufs

extension RangeTestConfigEntity {
	convenience init(config: ModuleConfig.RangeTestConfig) {
		self.init()
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
