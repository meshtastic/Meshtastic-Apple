import CoreBluetooth
import CoreData
import MeshtasticProtobufs
import SwiftProtobuf

extension BLEManager {
	// MARK: - user

	func saveUser(
		config: User,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setOwner = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message)
	}

	@discardableResult
	func saveLicensedUser(
		ham: HamParameters,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setHamMode = ham

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message)
	}

	// MARK: - device

	@discardableResult
	func requestBluetoothConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.bluetoothConfig
		)
	}

	@discardableResult
	func saveBluetoothConfig(
		config: Config.BluetoothConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.bluetooth = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertBluetoothConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestDeviceConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.deviceConfig
		)
	}

	@discardableResult
	func saveDeviceConfig(
		config: Config.DeviceConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.device = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertDeviceConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestDisplayConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.displayConfig
		)
	}

	@discardableResult
	func saveDisplayConfig(
		config: Config.DisplayConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.display = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertDisplayConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestLoRaConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.loraConfig
		)
	}

	@discardableResult
	func saveLoRaConfig(
		config: Config.LoRaConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.lora = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertLoRaConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestNetworkConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.networkConfig
		)
	}

	@discardableResult
	func saveNetworkConfig(
		config: Config.NetworkConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.network = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertNetworkConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestPositionConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.positionConfig
		)
	}

	@discardableResult
	func savePositionConfig(
		config: Config.PositionConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.position = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertPositionConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func setFixedPosition(
		fromUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		guard let positionPacket = getPhonePosition() else {
			return false
		}

		var message = AdminMessage()
		message.setFixedPosition = positionPacket

		return saveConfig(from: fromUser, to: fromUser, index: adminIndex, message: message) != 0
	}

	@discardableResult
	func removeFixedPosition(
		fromUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.removeFixedPosition = true

		return saveConfig(from: fromUser, to: fromUser, index: adminIndex, message: message) != 0
	}

	@discardableResult
	func requestPowerConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.powerConfig
		)
	}

	@discardableResult
	func savePowerConfig(
		config: Config.PowerConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.power = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertPowerConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	// MARK: - modules

	@discardableResult
	func requestMQTTModuleConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		requestConfig(
			from: fromUser,
			to: toUser,
			index: adminIndex,
			type: AdminMessage.ModuleConfigType.mqttConfig
		)
	}

	@discardableResult
	func saveMQTTConfig(
		config: ModuleConfig.MQTTConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setModuleConfig.mqtt = config

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) {
			upsertMqttModuleConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}
	
	// MARK: - commands

	func sendShutdown(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.shutdownSeconds = 5

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) != 0
	}
	
	func sendReboot(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.rebootSeconds = 5

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) != 0
	}
	
	func sendRebootOta(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.rebootOtaSeconds = 5

		return saveConfig(from: fromUser, to: toUser, index: adminIndex, message: message) != 0
	}
	
	func sendFactoryReset(
		fromUser: UserEntity,
		toUser: UserEntity
	) -> Bool {
		var message = AdminMessage()
		message.factoryResetDevice = 5

		return saveConfig(from: fromUser, to: toUser, message: message) != 0
	}
	
	func sendNodeDBReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var message = AdminMessage()
		message.nodedbReset = 5

		return saveConfig(from: fromUser, to: toUser, message: message) != 0
	}
	

	// MARK: - common

	@discardableResult
	func requestDeviceMetadata(
		from: UserEntity,
		to: UserEntity,
		index: Int32,
		context: NSManagedObjectContext
	) -> Int64 {
		var message = AdminMessage()
		message.getDeviceMetadataRequest = true

		guard let packet = createPacket(
			for: message,
			from: from,
			to: to,
			index: index,
			wantResponse: true
		) else {
			return 0
		}

		return sendAdminPacket(packet)
	}

	private func requestConfig(
		from: UserEntity,
		to: UserEntity,
		index: Int32,
		type: AdminMessage.ConfigType,
		onSuccess: (() -> Void)? = nil
	) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = type

		guard let packet = createPacket(
			for: adminPacket,
			from: from,
			to: to,
			index: index,
			wantResponse: true
		) else {
			return false
		}

		return sendAdminPacket(packet, onSuccess: onSuccess) != 0
	}

	private func requestConfig(
		from: UserEntity,
		to: UserEntity,
		index: Int32,
		type: AdminMessage.ModuleConfigType,
		onSuccess: (() -> Void)? = nil
	) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = type

		guard let packet = createPacket(
			for: adminPacket,
			from: from,
			to: to,
			index: index,
			wantResponse: true
		) else {
			return false
		}

		return sendAdminPacket(packet, onSuccess: onSuccess) != 0
	}

	private func saveConfig(
		from: UserEntity,
		to: UserEntity,
		index: Int32? = nil,
		message: AdminMessage,
		onSuccess: (() -> Void)? = nil
	) -> Int64 {
		guard let packet = createPacket(
			for: message,
			from: from,
			to: to,
			index: index,
			wantResponse: true
		) else {
			return 0
		}

		return sendAdminPacket(packet, onSuccess: onSuccess)
	}

	private func createPacket(
		for adminMessage: AdminMessage,
		from: UserEntity,
		to: UserEntity,
		index: Int32? = nil,
		wantResponse: Bool = false
	) -> MeshPacket? {
		guard let adminData: Data = try? adminMessage.serializedData() else {
			return nil
		}

		var dataMessage = DataMessage()
		dataMessage.payload = adminData
		dataMessage.portnum = PortNum.adminApp
		dataMessage.wantResponse = wantResponse

		var meshPacket = MeshPacket()
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.to = UInt32(from.num)
		meshPacket.from = UInt32(to.num)
		meshPacket.priority = .reliable
		meshPacket.wantAck = true
		meshPacket.decoded = dataMessage
		if let index {
			meshPacket.channel = UInt32(index)
		}

		return meshPacket
	}

	func sendAdminPacket(
		_ packet: MeshPacket,
		onSuccess: (() -> Void)? = nil
	) -> Int64 {
		var toRadio = ToRadio()
		toRadio.packet = packet

		guard
			let connectedDevice = getConnectedDevice(),
			let binaryData: Data = try? toRadio.serializedData()
		else {
			return 0
		}

		connectedDevice.peripheral.writeValue(
			binaryData,
			for: characteristicToRadio,
			type: .withResponse
		)

		onSuccess?()

		return Int64(packet.id)
	}
}
