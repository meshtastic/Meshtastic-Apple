import CoreData
import MeshtasticProtobufs

extension MQTTConfigEntity {
	convenience init(
		context: NSManagedObjectContext,
		config: ModuleConfig.MQTTConfig
	) {
		self.init(context: context)
		self.enabled = config.enabled
		self.proxyToClientEnabled = config.proxyToClientEnabled
		self.address = config.address
		self.username = config.username
		self.password = config.password
		self.root = config.root
		self.encryptionEnabled = config.encryptionEnabled
		self.jsonEnabled = config.jsonEnabled
		self.tlsEnabled = config.tlsEnabled
		self.mapReportingEnabled = config.mapReportingEnabled
		self.mapPositionPrecision = Int32(config.mapReportSettings.positionPrecision)
		self.mapPublishIntervalSecs = Int32(config.mapReportSettings.publishIntervalSecs)
	}

	func update(with config: ModuleConfig.MQTTConfig) {
		enabled = config.enabled
		proxyToClientEnabled = config.proxyToClientEnabled
		address = config.address
		username = config.username
		password = config.password
		root = config.root
		encryptionEnabled = config.encryptionEnabled
		jsonEnabled = config.jsonEnabled
		tlsEnabled = config.tlsEnabled
		mapReportingEnabled = config.mapReportingEnabled
		mapPositionPrecision = Int32(config.mapReportSettings.positionPrecision)
		mapPublishIntervalSecs = Int32(config.mapReportSettings.publishIntervalSecs)
	}
}
