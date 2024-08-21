import CoreBluetooth
import CoreData
import MeshtasticProtobufs
import SwiftProtobuf

// swiftlint:disable file_length
final class NodeConfig: ObservableObject {
	private static var configNonce: UInt32 = 1

	private let bleManager: BLEManager
	private let context: NSManagedObjectContext

	init(
		bleManager: BLEManager,
		context: NSManagedObjectContext
	) {
		self.bleManager = bleManager
		self.context = context
	}

	// MARK: - user

	func saveUser(
		config: User,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setOwner = config

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .userSave
		)
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .licensedUserSave
		)
	}

	// MARK: - node

	@discardableResult
	func saveFavoriteNode(
		node: NodeInfoEntity,
		connectedNodeNum: Int64
	) -> Bool {
		var message = AdminMessage()
		message.setFavoriteNode = UInt32(node.num)

		return sendRequest(
			to: connectedNodeNum,
			message: message,
			event: .favoriteNodeSet
		) != 0
	}

	func removeFavoriteNode(
		node: NodeInfoEntity,
		connectedNodeNum: Int64
	) -> Bool {
		var message = AdminMessage()
		message.setFavoriteNode = UInt32(node.num)

		return sendRequest(
			to: connectedNodeNum,
			message: message,
			event: .favoriteNodeRemove
		) != 0
	}

	// MARK: - channel

	@discardableResult
	func requestChannel(
		channel: Channel,
		fromUser: UserEntity,
		toUser: UserEntity
	) -> Int64 {
		var message = AdminMessage()
		message.getChannelRequest = UInt32(channel.index + 1)

		return sendRequest(
			to: toUser,
			from: fromUser,
			message: message,
			event: .channel
		)
	}

	@discardableResult
	func saveChannel(
		channel: Channel,
		fromUser: UserEntity,
		toUser: UserEntity
	) -> Int64 {
		return saveChannel(
			channel: channel,
			fromUser: fromUser.num,
			toUser: toUser.num
		)
	}

	@discardableResult
	func saveChannel(
		channel: Channel,
		fromUser: Int64,
		toUser: Int64
	) -> Int64 {
		var message = AdminMessage()
		message.setChannel = channel

		return sendRequest(
			to: toUser,
			from: fromUser,
			message: message,
			event: .channelSave
		)
	}

	// MARK: - device

	@discardableResult
	func requestBluetoothConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.bluetoothConfig,
			event: .bluetoothConfig
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .bluetoothConfigSave
		) {
			upsertBluetoothConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestDeviceConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.deviceConfig,
			event: .deviceConfig
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .deviceConfigSave
		) {
			upsertDeviceConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestDisplayConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.displayConfig,
			event: .displayConfig
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .displayConfigSave
		) {
			upsertDisplayConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestLoRaConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.loraConfig,
			event: .loraConfig
		)
	}

	@discardableResult
	func saveLoRaConfig(
		config: Config.LoRaConfig,
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Int64 {
		return saveLoRaConfig(
			config: config,
			fromUser: fromUser.num,
			toUser: toUser.num,
			adminIndex: adminIndex
		)
	}

	@discardableResult
	func saveLoRaConfig(
		config: Config.LoRaConfig,
		fromUser: Int64,
		toUser: Int64,
		adminIndex: Int32
	) -> Int64 {
		var message = AdminMessage()
		message.setConfig.lora = config

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .loraConfigSave
		) {
			upsertLoRaConfigPacket(config: config, nodeNum: toUser, context: self.context)
		}
	}

	@discardableResult
	func requestNetworkConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.networkConfig,
			event: .networkConfig
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .networkConfigSave
		) {
			upsertNetworkConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func requestPositionConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.positionConfig,
			event: .positionConfig
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .positionConfigSave
		) {
			upsertPositionConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	@discardableResult
	func setFixedPosition(
		fromUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		guard let positionPacket = bleManager.getPhonePosition() else {
			return false
		}

		var message = AdminMessage()
		message.setFixedPosition = positionPacket

		return sendRequest(
			to: fromUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .fixedPositionSet
		) != 0
	}

	@discardableResult
	func removeFixedPosition(
		fromUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.removeFixedPosition = true

		return sendRequest(
			to: fromUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .fixedPositionRemove
		) != 0
	}

	@discardableResult
	func requestPowerConfig(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ConfigType.powerConfig,
			event: .powerConfig
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .powerConfigSave
		) {
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
		sendConfigRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			type: AdminMessage.ModuleConfigType.mqttConfig,
			event: .mqttConfig
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

		return sendRequest(
			to: toUser,
			from: fromUser,
			index: adminIndex,
			message: message,
			event: .mqttConfigSave
		) {
			upsertMqttModuleConfigPacket(config: config, nodeNum: toUser.num, context: self.context)
		}
	}

	// MARK: - requests

	func sendWantConfig() -> UInt32 {
		guard bleManager.characteristicFromRadio != nil else {
			bleManager.setIsInvalidFwVersion()

			AnalyticEvents.trackBLEEvent(for: .wantConfig, status: .failureProcess)
			return UInt32.min
		}

		Self.configNonce += 1
		let nonce = Self.configNonce

		var toRadio = ToRadio()
		toRadio.wantConfigID = nonce

		guard
			let connectedDevice = bleManager.getConnectedDevice(),
			let binaryData: Data = try? toRadio.serializedData()
		else {
			AnalyticEvents.trackBLEEvent(for: .wantConfig, status: .failureProcess)
			return UInt32.min
		}

		connectedDevice.peripheral.writeValue(
			binaryData,
			for: bleManager.characteristicToRadio,
			type: .withResponse
		)

		connectedDevice.peripheral.readValue(
			for: bleManager.characteristicFromRadio
		)

		AnalyticEvents.trackBLEEvent(for: .wantConfig, status: .success)
		return nonce
	}

	@discardableResult
	func sendShutdown(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.shutdownSeconds = 5

		return sendRequest(to: toUser, from: fromUser, index: adminIndex, message: message, event: .shutdown) != 0
	}

	@discardableResult
	func sendReboot(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.rebootSeconds = 5

		return sendRequest(to: toUser, from: fromUser, index: adminIndex, message: message, event: .reboot) != 0
	}

	@discardableResult
	func sendRebootOta(
		fromUser: UserEntity,
		toUser: UserEntity,
		adminIndex: Int32
	) -> Bool {
		var message = AdminMessage()
		message.rebootOtaSeconds = 5

		return sendRequest(to: toUser, from: fromUser, index: adminIndex, message: message, event: .rebootOTA) != 0
	}

	@discardableResult
	func sendFactoryReset(
		fromUser: UserEntity,
		toUser: UserEntity
	) -> Bool {
		var message = AdminMessage()
		message.factoryResetDevice = 5

		return sendRequest(to: toUser, from: fromUser, message: message, event: .factoryReset) != 0
	}

	@discardableResult
	func sendNodeDBReset(fromUser: UserEntity, toUser: UserEntity) -> Bool {
		var message = AdminMessage()
		message.nodedbReset = 5

		return sendRequest(to: toUser, from: fromUser, message: message, event: .resetDB) != 0
	}

	@discardableResult
	func removeNode(node: NodeInfoEntity, connectedNodeNum: Int64) -> Bool {
		var message = AdminMessage()
		message.removeByNodenum = UInt32(node.num)

		guard sendRequest(to: connectedNodeNum, message: message, event: .nodeRemove) != 0 else {
			return false
		}

		if let user = node.user {
			context.delete(user)
		}
		context.delete(node)

		do {
			try context.save()

			return true
		}
		catch {
			context.rollback()

			return false
		}
	}

	@discardableResult
	func requestDeviceMetadata(
		to: UserEntity,
		from: UserEntity,
		index: Int32,
		context: NSManagedObjectContext
	) -> Int64 {
		var message = AdminMessage()
		message.getDeviceMetadataRequest = true

		guard let packet = createPacket(
			for: message,
			to: to.num,
			from: from.num,
			index: index,
			wantResponse: true
		) else {
			AnalyticEvents.trackBLEEvent(for: .deviceMetadata, status: .failureProcess)
			return 0
		}

		let status = sendAdminPacket(packet)
		AnalyticEvents.trackBLEEvent(for: .deviceMetadata, status: status != 0 ? .success : .failureSend)
		return status
	}

	@discardableResult
	func getCannedMessageModuleMessages(destNum: Int64, wantResponse: Bool) -> Bool {
		var message = AdminMessage()
		message.getCannedMessageModuleMessagesRequest = true

		return sendRequest(to: destNum, message: message, event: .cannedMessages) != 0
	}

	// MARK: - common

	private func sendConfigRequest(
		to: UserEntity,
		from: UserEntity,
		index: Int32,
		type: AdminMessage.ConfigType,
		event: AnalyticEvents.BLERequest,
		onSuccess: (() -> Void)? = nil
	) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.getConfigRequest = type

		guard let packet = createPacket(
			for: adminPacket,
			to: to.num,
			from: from.num,
			index: index,
			wantResponse: true
		) else {
			AnalyticEvents.trackBLEEvent(for: event, status: .failureProcess)
			return false
		}

		let status = sendAdminPacket(packet, onSuccess: onSuccess) != 0
		AnalyticEvents.trackBLEEvent(for: event, status: status ? .success : .failureSend)

		return status
	}

	private func sendConfigRequest(
		to: UserEntity,
		from: UserEntity,
		index: Int32,
		type: AdminMessage.ModuleConfigType,
		event: AnalyticEvents.BLERequest,
		onSuccess: (() -> Void)? = nil
	) -> Bool {
		var adminPacket = AdminMessage()
		adminPacket.getModuleConfigRequest = type

		guard let packet = createPacket(
			for: adminPacket,
			to: to.num,
			from: from.num,
			index: index,
			wantResponse: true
		) else {
			AnalyticEvents.trackBLEEvent(for: event, status: .failureProcess)
			return false
		}

		let status = sendAdminPacket(packet, onSuccess: onSuccess) != 0
		AnalyticEvents.trackBLEEvent(for: event, status: status ? .success : .failureSend)

		return status
	}

	private func sendRequest(
		to: UserEntity,
		from: UserEntity,
		index: Int32? = nil,
		message: AdminMessage,
		event: AnalyticEvents.BLERequest,
		onSuccess: (() -> Void)? = nil
	) -> Int64 {
		guard let packet = createPacket(
			for: message,
			to: to.num,
			from: from.num,
			index: index,
			wantResponse: true
		) else {
			AnalyticEvents.trackBLEEvent(for: event, status: .failureProcess)
			return 0
		}

		let status = sendAdminPacket(packet, onSuccess: onSuccess)
		AnalyticEvents.trackBLEEvent(for: event, status: status != 0 ? .success : .failureSend)

		return status
	}

	private func sendRequest(
		to: Int64,
		from: Int64? = nil,
		index: Int32? = nil,
		message: AdminMessage,
		event: AnalyticEvents.BLERequest,
		onSuccess: (() -> Void)? = nil
	) -> Int64 {
		guard let packet = createPacket(
			for: message,
			to: to,
			from: from,
			index: index,
			wantResponse: true
		) else {
			AnalyticEvents.trackBLEEvent(for: event, status: .failureProcess)
			return 0
		}

		let status = sendAdminPacket(packet, onSuccess: onSuccess)
		AnalyticEvents.trackBLEEvent(for: event, status: status != 0 ? .success : .failureSend)

		return status
	}

	private func createPacket(
		for adminMessage: AdminMessage,
		to: Int64,
		from: Int64? = nil,
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
		meshPacket.to = UInt32(to)
		if let from {
			meshPacket.from = UInt32(from)
		}
		meshPacket.priority = .reliable
		meshPacket.wantAck = true
		meshPacket.decoded = dataMessage
		if let index {
			meshPacket.channel = UInt32(index)
		}

		return meshPacket
	}

	private func sendAdminPacket(
		_ packet: MeshPacket,
		onSuccess: (() -> Void)? = nil
	) -> Int64 {
		var toRadio = ToRadio()
		toRadio.packet = packet

		guard
			let connectedDevice = bleManager.getConnectedDevice(),
			let binaryData: Data = try? toRadio.serializedData()
		else {
			return 0
		}

		connectedDevice.peripheral.writeValue(
			binaryData,
			for: bleManager.characteristicToRadio,
			type: .withResponse
		)

		onSuccess?()

		return Int64(packet.id)
	}
}
// swiftlint:enable file_length
