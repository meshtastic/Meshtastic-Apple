import CoreData
import MeshtasticProtobufs

extension ExternalNotificationConfigEntity {
	convenience init(
		context: NSManagedObjectContext,
		config: ModuleConfig.ExternalNotificationConfig
	) {
		self.init(context: context)
		self.enabled = config.enabled
		self.usePWM = config.usePwm
		self.alertBell = config.alertBell
		self.alertBellBuzzer = config.alertBellBuzzer
		self.alertBellVibra = config.alertBellVibra
		self.alertMessage = config.alertMessage
		self.alertMessageBuzzer = config.alertMessageBuzzer
		self.alertMessageVibra = config.alertMessageVibra
		self.active = config.active
		self.output = Int32(config.output)
		self.outputBuzzer = Int32(config.outputBuzzer)
		self.outputVibra = Int32(config.outputVibra)
		self.outputMilliseconds = Int32(config.outputMs)
		self.nagTimeout = Int32(config.nagTimeout)
		self.useI2SAsBuzzer = config.useI2SAsBuzzer
	}

	func update(with config: ModuleConfig.ExternalNotificationConfig) {
		enabled = config.enabled
		usePWM = config.usePwm
		alertBell = config.alertBell
		alertBellBuzzer = config.alertBellBuzzer
		alertBellVibra = config.alertBellVibra
		alertMessage = config.alertMessage
		alertMessageBuzzer = config.alertMessageBuzzer
		alertMessageVibra = config.alertMessageVibra
		active = config.active
		output = Int32(config.output)
		outputBuzzer = Int32(config.outputBuzzer)
		outputVibra = Int32(config.outputVibra)
		outputMilliseconds = Int32(config.outputMs)
		nagTimeout = Int32(config.nagTimeout)
		useI2SAsBuzzer = config.useI2SAsBuzzer
	}
}
