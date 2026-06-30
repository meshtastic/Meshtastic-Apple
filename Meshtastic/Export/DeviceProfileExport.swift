//
//  DeviceProfileExport.swift
//  Meshtastic
//
//  Builds a `DeviceProfile` protobuf from the locally-persisted SwiftData config entities so the
//  connected node's whole configuration can be exported to a file (matching the Android app and the
//  `meshtastic` CLI). Each converter is the inverse of the proto -> entity mapping in
//  UpdateSwiftData.swift; keep the two in sync when adding config fields.
//

import Foundation
import MeshtasticProtobufs

// MARK: - Device configs (LocalConfig)

extension DeviceConfigEntity {
	var protoConfig: Config.DeviceConfig {
		var config = Config.DeviceConfig()
		config.role = .init(rawValue: Int(role)) ?? config.role
		config.buttonGpio = UInt32(truncatingIfNeeded: buttonGpio)
		config.buzzerGpio = UInt32(truncatingIfNeeded: buzzerGpio)
		config.rebroadcastMode = .init(rawValue: Int(rebroadcastMode)) ?? config.rebroadcastMode
		config.nodeInfoBroadcastSecs = UInt32(truncatingIfNeeded: nodeInfoBroadcastSecs)
		config.doubleTapAsButtonPress = doubleTapAsButtonPress
		config.disableTripleClick = !tripleClickAsAdHocPing
		config.ledHeartbeatDisabled = !ledHeartbeatEnabled
		config.isManaged = isManaged
		config.tzdef = tzdef ?? ""
		return config
	}
}

extension DisplayConfigEntity {
	var protoConfig: Config.DisplayConfig {
		var config = Config.DisplayConfig()
		config.screenOnSecs = UInt32(truncatingIfNeeded: screenOnSeconds)
		config.autoScreenCarouselSecs = UInt32(truncatingIfNeeded: screenCarouselInterval)
		config.compassNorthTop = compassNorthTop
		config.compassOrientation = .init(rawValue: Int(compassOrientation)) ?? config.compassOrientation
		config.flipScreen = flipScreen
		config.oled = .init(rawValue: Int(oledType)) ?? config.oled
		config.displaymode = .init(rawValue: Int(displayMode)) ?? config.displaymode
		config.units = .init(rawValue: Int(units)) ?? config.units
		config.headingBold = headingBold
		config.use12HClock = use12HClock
		return config
	}
}

extension LoRaConfigEntity {
	var protoConfig: Config.LoRaConfig {
		var config = Config.LoRaConfig()
		config.region = .init(rawValue: Int(regionCode)) ?? config.region
		config.usePreset = usePreset
		config.modemPreset = .init(rawValue: Int(modemPreset)) ?? config.modemPreset
		config.bandwidth = UInt32(truncatingIfNeeded: bandwidth)
		config.spreadFactor = UInt32(truncatingIfNeeded: spreadFactor)
		config.codingRate = UInt32(truncatingIfNeeded: codingRate)
		config.frequencyOffset = frequencyOffset
		config.overrideFrequency = overrideFrequency
		config.overrideDutyCycle = overrideDutyCycle
		config.hopLimit = UInt32(truncatingIfNeeded: hopLimit)
		config.txPower = txPower
		config.txEnabled = txEnabled
		config.channelNum = UInt32(truncatingIfNeeded: channelNum)
		config.sx126XRxBoostedGain = sx126xRxBoostedGain
		config.ignoreMqtt = ignoreMqtt
		config.configOkToMqtt = okToMqtt
		return config
	}
}

extension NetworkConfigEntity {
	var protoConfig: Config.NetworkConfig {
		var config = Config.NetworkConfig()
		config.wifiEnabled = wifiEnabled
		config.wifiSsid = wifiSsid ?? ""
		config.wifiPsk = wifiPsk ?? ""
		config.ntpServer = ntpServer ?? ""
		config.ethEnabled = ethEnabled
		config.enabledProtocols = UInt32(truncatingIfNeeded: enabledProtocols)
		config.addressMode = .init(rawValue: Int(addressMode)) ?? config.addressMode
		config.rsyslogServer = rsyslogServer ?? ""
		config.ipv4Config.ip = UInt32(bitPattern: ip)
		config.ipv4Config.gateway = UInt32(bitPattern: gateway)
		config.ipv4Config.subnet = UInt32(bitPattern: subnet)
		config.ipv4Config.dns = UInt32(bitPattern: dns)
		return config
	}
}

extension PositionConfigEntity {
	var protoConfig: Config.PositionConfig {
		var config = Config.PositionConfig()
		config.positionBroadcastSmartEnabled = smartPositionEnabled
		config.gpsEnabled = deviceGpsEnabled
		config.gpsMode = .init(rawValue: Int(gpsMode)) ?? config.gpsMode
		config.rxGpio = UInt32(truncatingIfNeeded: rxGpio)
		config.txGpio = UInt32(truncatingIfNeeded: txGpio)
		config.gpsEnGpio = UInt32(truncatingIfNeeded: gpsEnGpio)
		config.fixedPosition = fixedPosition
		config.positionBroadcastSecs = UInt32(truncatingIfNeeded: positionBroadcastSeconds)
		config.broadcastSmartMinimumIntervalSecs = UInt32(truncatingIfNeeded: broadcastSmartMinimumIntervalSecs)
		config.broadcastSmartMinimumDistance = UInt32(truncatingIfNeeded: broadcastSmartMinimumDistance)
		config.gpsUpdateInterval = UInt32(truncatingIfNeeded: gpsUpdateInterval)
		config.positionFlags = UInt32(truncatingIfNeeded: positionFlags)
		return config
	}
}

extension PowerConfigEntity {
	var protoConfig: Config.PowerConfig {
		var config = Config.PowerConfig()
		config.adcMultiplierOverride = adcMultiplierOverride
		config.deviceBatteryInaAddress = UInt32(truncatingIfNeeded: deviceBatteryInaAddress)
		config.isPowerSaving = isPowerSaving
		config.lsSecs = UInt32(truncatingIfNeeded: lsSecs)
		config.minWakeSecs = UInt32(truncatingIfNeeded: minWakeSecs)
		config.onBatteryShutdownAfterSecs = UInt32(truncatingIfNeeded: onBatteryShutdownAfterSecs)
		config.waitBluetoothSecs = UInt32(truncatingIfNeeded: waitBluetoothSecs)
		return config
	}
}

extension BluetoothConfigEntity {
	var protoConfig: Config.BluetoothConfig {
		var config = Config.BluetoothConfig()
		config.enabled = enabled
		config.mode = .init(rawValue: Int(mode)) ?? config.mode
		config.fixedPin = UInt32(truncatingIfNeeded: fixedPin)
		return config
	}
}

extension SecurityConfigEntity {
	var protoConfig: Config.SecurityConfig {
		var config = Config.SecurityConfig()
		config.publicKey = publicKey ?? Data()
		config.privateKey = privateKey ?? Data()
		// The proto `adminKey` is a positional repeated field (index 0/1/2 map back to
		// adminKey/adminKey2/adminKey3 on import), so preserve slots — nil/empty middle slots stay
		// as empty entries and only trailing empties are trimmed.
		var adminKeys = [adminKey, adminKey2, adminKey3].map { $0 ?? Data() }
		while let last = adminKeys.last, last.isEmpty { adminKeys.removeLast() }
		config.adminKey = adminKeys
		config.isManaged = isManaged
		config.serialEnabled = serialEnabled
		config.debugLogApiEnabled = debugLogApiEnabled
		config.adminChannelEnabled = adminChannelEnabled
		return config
	}
}

// MARK: - Module configs (LocalModuleConfig)

extension MQTTConfigEntity {
	var protoConfig: ModuleConfig.MQTTConfig {
		var config = ModuleConfig.MQTTConfig()
		config.enabled = enabled
		config.proxyToClientEnabled = proxyToClientEnabled
		config.address = address ?? ""
		config.username = username ?? ""
		config.password = password ?? ""
		config.root = root ?? ""
		config.encryptionEnabled = encryptionEnabled
		config.jsonEnabled = jsonEnabled
		config.tlsEnabled = tlsEnabled
		config.mapReportingEnabled = mapReportingEnabled
		config.mapReportSettings.positionPrecision = UInt32(truncatingIfNeeded: mapPositionPrecision)
		config.mapReportSettings.publishIntervalSecs = UInt32(truncatingIfNeeded: mapPublishIntervalSecs)
		config.mapReportSettings.shouldReportLocation = mapReportingShouldReportLocation
		return config
	}
}

extension SerialConfigEntity {
	var protoConfig: ModuleConfig.SerialConfig {
		var config = ModuleConfig.SerialConfig()
		config.enabled = enabled
		config.echo = echo
		config.rxd = UInt32(truncatingIfNeeded: rxd)
		config.txd = UInt32(truncatingIfNeeded: txd)
		config.baud = .init(rawValue: Int(baudRate)) ?? config.baud
		config.timeout = UInt32(truncatingIfNeeded: timeout)
		config.mode = .init(rawValue: Int(mode)) ?? config.mode
		config.overrideConsoleSerialPort = overrideConsoleSerialPort
		return config
	}
}

extension ExternalNotificationConfigEntity {
	var protoConfig: ModuleConfig.ExternalNotificationConfig {
		var config = ModuleConfig.ExternalNotificationConfig()
		config.enabled = enabled
		config.usePwm = usePWM
		config.alertBell = alertBell
		config.alertBellBuzzer = alertBellBuzzer
		config.alertBellVibra = alertBellVibra
		config.alertMessage = alertMessage
		config.alertMessageBuzzer = alertMessageBuzzer
		config.alertMessageVibra = alertMessageVibra
		config.active = active
		config.output = UInt32(truncatingIfNeeded: output)
		config.outputBuzzer = UInt32(truncatingIfNeeded: outputBuzzer)
		config.outputVibra = UInt32(truncatingIfNeeded: outputVibra)
		config.outputMs = UInt32(truncatingIfNeeded: outputMilliseconds)
		config.nagTimeout = UInt32(truncatingIfNeeded: nagTimeout)
		config.useI2SAsBuzzer = useI2SAsBuzzer
		return config
	}
}

extension StoreForwardConfigEntity {
	var protoConfig: ModuleConfig.StoreForwardConfig {
		var config = ModuleConfig.StoreForwardConfig()
		config.enabled = enabled
		config.isServer = isRouter
		config.heartbeat = heartbeat
		config.records = UInt32(truncatingIfNeeded: records)
		config.historyReturnMax = UInt32(truncatingIfNeeded: historyReturnMax)
		config.historyReturnWindow = UInt32(truncatingIfNeeded: historyReturnWindow)
		return config
	}
}

extension RangeTestConfigEntity {
	var protoConfig: ModuleConfig.RangeTestConfig {
		var config = ModuleConfig.RangeTestConfig()
		config.enabled = enabled
		config.sender = UInt32(truncatingIfNeeded: sender)
		config.save = save
		return config
	}
}

extension TelemetryConfigEntity {
	var protoConfig: ModuleConfig.TelemetryConfig {
		var config = ModuleConfig.TelemetryConfig()
		config.deviceUpdateInterval = UInt32(truncatingIfNeeded: deviceUpdateInterval)
		config.deviceTelemetryEnabled = deviceTelemetryEnabled
		config.environmentUpdateInterval = UInt32(truncatingIfNeeded: environmentUpdateInterval)
		config.environmentMeasurementEnabled = environmentMeasurementEnabled
		config.environmentScreenEnabled = environmentScreenEnabled
		config.environmentDisplayFahrenheit = environmentDisplayFahrenheit
		config.airQualityEnabled = airQualityEnabled
		config.airQualityInterval = UInt32(truncatingIfNeeded: airQualityInterval)
		config.powerMeasurementEnabled = powerMeasurementEnabled
		config.powerUpdateInterval = UInt32(truncatingIfNeeded: powerUpdateInterval)
		config.powerScreenEnabled = powerScreenEnabled
		return config
	}
}

extension CannedMessageConfigEntity {
	var protoConfig: ModuleConfig.CannedMessageConfig {
		var config = ModuleConfig.CannedMessageConfig()
		config.enabled = enabled
		config.sendBell = sendBell
		config.rotary1Enabled = rotary1Enabled
		config.updown1Enabled = updown1Enabled
		config.inputbrokerPinA = UInt32(truncatingIfNeeded: inputbrokerPinA)
		config.inputbrokerPinB = UInt32(truncatingIfNeeded: inputbrokerPinB)
		config.inputbrokerPinPress = UInt32(truncatingIfNeeded: inputbrokerPinPress)
		config.inputbrokerEventCw = .init(rawValue: Int(inputbrokerEventCw)) ?? config.inputbrokerEventCw
		config.inputbrokerEventCcw = .init(rawValue: Int(inputbrokerEventCcw)) ?? config.inputbrokerEventCcw
		config.inputbrokerEventPress = .init(rawValue: Int(inputbrokerEventPress)) ?? config.inputbrokerEventPress
		return config
	}
}

extension AudioConfigEntity {
	var protoConfig: ModuleConfig.AudioConfig {
		var config = ModuleConfig.AudioConfig()
		config.codec2Enabled = codec2Enabled
		config.pttPin = UInt32(truncatingIfNeeded: pttPin)
		config.bitrate = .init(rawValue: Int(bitrate)) ?? config.bitrate
		config.i2SWs = UInt32(truncatingIfNeeded: i2sWs)
		config.i2SSd = UInt32(truncatingIfNeeded: i2sSd)
		config.i2SDin = UInt32(truncatingIfNeeded: i2sDin)
		config.i2SSck = UInt32(truncatingIfNeeded: i2sSck)
		return config
	}
}

extension NeighborInfoConfigEntity {
	var protoConfig: ModuleConfig.NeighborInfoConfig {
		var config = ModuleConfig.NeighborInfoConfig()
		config.enabled = enabled
		config.updateInterval = UInt32(truncatingIfNeeded: updateInterval)
		config.transmitOverLora = transmitOverLora
		return config
	}
}

extension AmbientLightingConfigEntity {
	var protoConfig: ModuleConfig.AmbientLightingConfig {
		var config = ModuleConfig.AmbientLightingConfig()
		config.ledState = ledState
		config.current = UInt32(truncatingIfNeeded: current)
		config.red = UInt32(truncatingIfNeeded: red)
		config.green = UInt32(truncatingIfNeeded: green)
		config.blue = UInt32(truncatingIfNeeded: blue)
		return config
	}
}

extension DetectionSensorConfigEntity {
	var protoConfig: ModuleConfig.DetectionSensorConfig {
		var config = ModuleConfig.DetectionSensorConfig()
		config.enabled = enabled
		config.sendBell = sendBell
		config.name = name ?? ""
		config.monitorPin = UInt32(truncatingIfNeeded: monitorPin)
		config.detectionTriggerType = .init(rawValue: Int(triggerType)) ?? config.detectionTriggerType
		config.usePullup = usePullup
		config.minimumBroadcastSecs = UInt32(truncatingIfNeeded: minimumBroadcastSecs)
		config.stateBroadcastSecs = UInt32(truncatingIfNeeded: stateBroadcastSecs)
		return config
	}
}

extension PaxCounterConfigEntity {
	var protoConfig: ModuleConfig.PaxcounterConfig {
		var config = ModuleConfig.PaxcounterConfig()
		config.enabled = enabled
		config.paxcounterUpdateInterval = UInt32(truncatingIfNeeded: updateInterval)
		config.wifiThreshold = wifiThreshold
		config.bleThreshold = bleThreshold
		return config
	}
}

extension TAKConfigEntity {
	var protoConfig: ModuleConfig.TAKConfig {
		var config = ModuleConfig.TAKConfig()
		config.role = .init(rawValue: Int(role)) ?? config.role
		config.team = .init(rawValue: Int(team)) ?? config.team
		return config
	}
}

extension TrafficManagementConfigEntity {
	var protoConfig: ModuleConfig.TrafficManagementConfig {
		var config = ModuleConfig.TrafficManagementConfig()
		// The proto's bool toggle fields were removed in favour of the "non-zero uint32 implies
		// enabled" convention, so only emit the surviving uint32 fields. The companion booleans
		// (positionDedupEnabled, rateLimitEnabled, …) are reconstructed from these on import
		// (see TrafficManagementConfig.setTrafficManagementValues).
		config.positionMinIntervalSecs = UInt32(truncatingIfNeeded: positionMinIntervalSecs)
		config.nodeinfoDirectResponseMaxHops = UInt32(truncatingIfNeeded: nodeinfoDirectResponseMaxHops)
		config.rateLimitWindowSecs = UInt32(truncatingIfNeeded: rateLimitWindowSecs)
		config.rateLimitMaxPackets = UInt32(truncatingIfNeeded: rateLimitMaxPackets)
		config.unknownPacketThreshold = UInt32(truncatingIfNeeded: unknownPacketThreshold)
		return config
	}
}

extension StatusMessageConfigEntity {
	var protoConfig: ModuleConfig.StatusMessageConfig {
		var config = ModuleConfig.StatusMessageConfig()
		config.nodeStatus = nodeStatus
		return config
	}
}

// MARK: - DeviceProfile assembly

extension NodeInfoEntity {

	/// Assembles a `DeviceProfile` from the node's persisted configuration. Only the configs that
	/// have been received from the device are included; missing configs are left at their proto
	/// defaults. This is the canonical export format shared with the Android app and CLI.
	func exportDeviceProfile() -> DeviceProfile {
		var profile = DeviceProfile()

		if let user {
			profile.longName = user.longName ?? ""
			profile.shortName = user.shortName ?? ""
		}

		var localConfig = LocalConfig()
		if let deviceConfig { localConfig.device = deviceConfig.protoConfig }
		if let positionConfig { localConfig.position = positionConfig.protoConfig }
		if let powerConfig { localConfig.power = powerConfig.protoConfig }
		if let networkConfig { localConfig.network = networkConfig.protoConfig }
		if let displayConfig { localConfig.display = displayConfig.protoConfig }
		if let loRaConfig { localConfig.lora = loRaConfig.protoConfig }
		if let bluetoothConfig { localConfig.bluetooth = bluetoothConfig.protoConfig }
		if let securityConfig { localConfig.security = securityConfig.protoConfig }
		profile.config = localConfig

		var localModuleConfig = LocalModuleConfig()
		if let mqttConfig { localModuleConfig.mqtt = mqttConfig.protoConfig }
		if let serialConfig { localModuleConfig.serial = serialConfig.protoConfig }
		if let externalNotificationConfig { localModuleConfig.externalNotification = externalNotificationConfig.protoConfig }
		if let storeForwardConfig { localModuleConfig.storeForward = storeForwardConfig.protoConfig }
		if let rangeTestConfig { localModuleConfig.rangeTest = rangeTestConfig.protoConfig }
		if let telemetryConfig { localModuleConfig.telemetry = telemetryConfig.protoConfig }
		if let cannedMessageConfig { localModuleConfig.cannedMessage = cannedMessageConfig.protoConfig }
		if let audioConfig { localModuleConfig.audio = audioConfig.protoConfig }
		if let neighborInfoConfig { localModuleConfig.neighborInfo = neighborInfoConfig.protoConfig }
		if let ambientLightingConfig { localModuleConfig.ambientLighting = ambientLightingConfig.protoConfig }
		if let detectionSensorConfig { localModuleConfig.detectionSensor = detectionSensorConfig.protoConfig }
		if let paxCounterConfig { localModuleConfig.paxcounter = paxCounterConfig.protoConfig }
		if let takConfig { localModuleConfig.tak = takConfig.protoConfig }
		if let trafficManagementConfig { localModuleConfig.trafficManagement = trafficManagementConfig.protoConfig }
		if let statusMessageConfig { localModuleConfig.statusmessage = statusMessageConfig.protoConfig }
		profile.moduleConfig = localModuleConfig

		if let ringtone = rtttlConfig?.ringtone, !ringtone.isEmpty {
			profile.ringtone = ringtone
		}
		if let messages = cannedMessageConfig?.messages, !messages.isEmpty {
			profile.cannedMessages = messages
		}

		if let channelURL = exportChannelURL() {
			profile.channelURL = channelURL
		}

		// Include the fixed position coordinates only when the device is actually using one.
		if positionConfig?.fixedPosition == true, let position = latestPosition,
		   position.latitudeI != 0 || position.longitudeI != 0 {
			var fixed = Position()
			fixed.latitudeI = position.latitudeI
			fixed.longitudeI = position.longitudeI
			fixed.altitude = position.altitude
			profile.fixedPosition = fixed
		}

		return profile
	}

	/// Builds the `meshtastic.org/e/` channel-set URL (LoRa config + all configured channels),
	/// mirroring the format produced by the Share Channels screen. Returns nil if there are no
	/// channels to share.
	private func exportChannelURL() -> String? {
		guard let loRaConfig, let channels = myInfo?.channels, !channels.isEmpty else { return nil }

		var channelSet = ChannelSet()
		channelSet.loraConfig = loRaConfig.protoConfig

		for channel in channels.sorted(by: { $0.index < $1.index }) where channel.role > 0 {
			var settings = ChannelSettings()
			settings.name = channel.name ?? ""
			settings.psk = channel.psk ?? Data()
			settings.id = UInt32(channel.id)
			settings.moduleSettings.positionPrecision = UInt32(channel.positionPrecision)
			settings.moduleSettings.isMuted = channel.mute
			channelSet.settings.append(settings)
		}

		guard !channelSet.settings.isEmpty,
			  let settingsString = try? channelSet.serializedData().base64EncodedString() else {
			return nil
		}
		return "https://meshtastic.org/e/#\(settingsString.base64ToBase64url())"
	}
}
