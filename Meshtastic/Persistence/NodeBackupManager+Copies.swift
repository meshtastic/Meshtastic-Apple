//
//  NodeBackupManager+Copies.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftData

// MARK: - Row copies (shared by restore and the backup merge)
// Each copy carries every stored field except relationships, which the caller links to rows in
// its own context. `NodeBackupRestoreFieldTests` checks that nothing is dropped: add new stored
// attributes here.
extension NodeBackupManager {

	/// Copies a trace route's hops and node positions onto `dst`, inserting them into `context`.
	nonisolated static func insertCopiedChildren(of src: TraceRouteEntity, onto dst: TraceRouteEntity, in context: ModelContext) {
		for srcHop in src.hops {
			let dstHop = TraceRouteHopEntity()
			dstHop.back = srcHop.back
			dstHop.index = srcHop.index
			dstHop.name = srcHop.name
			dstHop.num = srcHop.num
			dstHop.snr = srcHop.snr
			dstHop.time = srcHop.time
			dstHop.traceRoute = dst
			context.insert(dstHop)
		}
		for srcPosition in src.nodePositions {
			let dstPosition = TraceRouteNodePositionEntity()
			dstPosition.num = srcPosition.num
			dstPosition.altitude = srcPosition.altitude
			dstPosition.heading = srcPosition.heading
			dstPosition.latitudeI = srcPosition.latitudeI
			dstPosition.longitudeI = srcPosition.longitudeI
			dstPosition.precisionBits = srcPosition.precisionBits
			dstPosition.satsInView = srcPosition.satsInView
			dstPosition.seqNo = srcPosition.seqNo
			dstPosition.snr = srcPosition.snr
			dstPosition.speed = srcPosition.speed
			dstPosition.time = srcPosition.time
			dstPosition.traceRoute = dst
			context.insert(dstPosition)
		}
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: UserEntity) -> UserEntity {
		let dst = UserEntity()
		dst.hwDisplayName = src.hwDisplayName
		dst.hwModel = src.hwModel
		dst.hwModelId = src.hwModelId
		dst.isLicensed = src.isLicensed
		dst.keyMatch = src.keyMatch
		dst.lastMessage = src.lastMessage
		dst.longName = src.longName
		dst.mute = src.mute
		dst.newPublicKey = src.newPublicKey
		dst.num = src.num
		dst.numString = src.numString
		dst.pkiEncrypted = src.pkiEncrypted
		dst.publicKey = src.publicKey
		dst.role = src.role
		dst.shortName = src.shortName
		dst.unmessagable = src.unmessagable
		dst.userId = src.userId
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: NodeInfoEntity) -> NodeInfoEntity {
		let dst = NodeInfoEntity()
		dst.bleName = src.bleName
		dst.channel = src.channel
		dst.favorite = src.favorite
		dst.firstHeard = src.firstHeard
		dst.hasBeenAdministered = src.hasBeenAdministered
		dst.hasXeddsaSigned = src.hasXeddsaSigned
		dst.heardOnCurrentLora = src.heardOnCurrentLora
		dst.hopsAway = src.hopsAway
		dst.id = src.id
		dst.ignored = src.ignored
		dst.isKeyManuallyVerified = src.isKeyManuallyVerified
		dst.lastHeard = src.lastHeard
		dst.nodeStatus = src.nodeStatus
		dst.num = src.num
		dst.peripheralId = src.peripheralId
		// User-edited and never re-sent by the radio, so a switch that dropped it lost it for good.
		dst.powerChannelLabels = src.powerChannelLabels
		dst.rssi = src.rssi
		dst.sessionExpiration = src.sessionExpiration
		dst.sessionPasskey = src.sessionPasskey
		dst.snr = src.snr
		dst.viaMqtt = src.viaMqtt
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: MyInfoEntity) -> MyInfoEntity {
		let dst = MyInfoEntity()
		dst.bleName = src.bleName
		dst.deviceId = src.deviceId
		dst.minAppVersion = src.minAppVersion
		dst.myNodeNum = src.myNodeNum
		dst.peripheralId = src.peripheralId
		dst.pioEnv = src.pioEnv
		dst.rebootCount = src.rebootCount
		dst.registered = src.registered
		dst.lastConnected = src.lastConnected
		dst.autoConnect = src.autoConnect
		dst.transport = src.transport
		dst.sortOrder = src.sortOrder
		dst.displayColor = src.displayColor
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: ChannelEntity) -> ChannelEntity {
		let dst = ChannelEntity()
		dst.downlinkEnabled = src.downlinkEnabled
		dst.id = src.id
		dst.index = src.index
		dst.mute = src.mute
		dst.name = src.name
		dst.positionPrecision = src.positionPrecision
		dst.psk = src.psk
		dst.role = src.role
		dst.uplinkEnabled = src.uplinkEnabled
		dst.channelKey = src.channelKey
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: DeviceMetadataEntity) -> DeviceMetadataEntity {
		let dst = DeviceMetadataEntity()
		dst.canShutdown = src.canShutdown
		dst.deviceStateVersion = src.deviceStateVersion
		dst.excludedModules = src.excludedModules
		dst.firmwareVersion = src.firmwareVersion
		dst.hasBluetooth = src.hasBluetooth
		dst.hasEthernet = src.hasEthernet
		dst.hasWifi = src.hasWifi
		dst.hasXeddsa = src.hasXeddsa
		dst.hwModel = src.hwModel
		dst.positionFlags = src.positionFlags
		dst.role = src.role
		dst.time = src.time
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: PositionEntity) -> PositionEntity {
		let dst = PositionEntity()
		dst.altitude = src.altitude
		dst.heading = src.heading
		dst.latest = src.latest
		dst.latitudeI = src.latitudeI
		dst.longitudeI = src.longitudeI
		dst.precisionBits = src.precisionBits
		dst.rssi = src.rssi
		dst.satsInView = src.satsInView
		dst.seqNo = src.seqNo
		dst.snr = src.snr
		dst.speed = src.speed
		dst.time = src.time
		dst.packetId = src.packetId
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: TelemetryEntity) -> TelemetryEntity {
		let dst = TelemetryEntity()
		dst.metricsType = src.metricsType
		dst.time = src.time
		dst.packetId = src.packetId
		dst.airUtilTx = src.airUtilTx
		dst.barometricPressure = src.barometricPressure
		dst.batteryLevel = src.batteryLevel
		dst.channelUtilization = src.channelUtilization
		dst.current = src.current
		dst.distance = src.distance
		dst.gasResistance = src.gasResistance
		dst.iaq = src.iaq
		dst.irLux = src.irLux
		dst.lux = src.lux
		dst.numOnlineNodes = src.numOnlineNodes
		dst.numPacketsRx = src.numPacketsRx
		dst.numPacketsRxBad = src.numPacketsRxBad
		dst.numPacketsTx = src.numPacketsTx
		dst.numRxDupe = src.numRxDupe
		dst.numTotalNodes = src.numTotalNodes
		dst.numTxRelay = src.numTxRelay
		dst.numTxRelayCanceled = src.numTxRelayCanceled
		dst.noiseFloor = src.noiseFloor
		dst.pm10Environmental = src.pm10Environmental
		dst.pm10Standard = src.pm10Standard
		dst.pm25Environmental = src.pm25Environmental
		dst.pm25Standard = src.pm25Standard
		dst.pm100Environmental = src.pm100Environmental
		dst.pm100Standard = src.pm100Standard
		dst.powerCh1Current = src.powerCh1Current
		dst.powerCh1Voltage = src.powerCh1Voltage
		dst.powerCh2Current = src.powerCh2Current
		dst.powerCh2Voltage = src.powerCh2Voltage
		dst.powerCh3Current = src.powerCh3Current
		dst.powerCh3Voltage = src.powerCh3Voltage
		dst.radiation = src.radiation
		dst.rainfall1H = src.rainfall1H
		dst.rainfall24H = src.rainfall24H
		dst.relativeHumidity = src.relativeHumidity
		dst.rssi = src.rssi
		dst.snr = src.snr
		dst.soilMoisture = src.soilMoisture
		dst.soilTemperature = src.soilTemperature
		dst.temperature = src.temperature
		dst.uptimeSeconds = src.uptimeSeconds
		dst.uvLux = src.uvLux
		dst.voltage = src.voltage
		dst.weight = src.weight
		dst.whiteLux = src.whiteLux
		dst.windDirection = src.windDirection
		dst.windGust = src.windGust
		dst.windLull = src.windLull
		dst.windSpeed = src.windSpeed
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: MessageEntity) -> MessageEntity {
		let dst = MessageEntity()
		dst.ackError = src.ackError
		dst.ackSNR = src.ackSNR
		dst.ackTimestamp = src.ackTimestamp
		dst.admin = src.admin
		dst.adminDescription = src.adminDescription
		dst.channel = src.channel
		dst.isEmoji = src.isEmoji
		dst.messageId = src.messageId
		dst.messagePayload = src.messagePayload
		dst.messagePayloadMarkdown = src.messagePayloadMarkdown
		dst.messagePayloadTranslated = src.messagePayloadTranslated
		dst.messagePayloadTranslatedMarkdown = src.messagePayloadTranslatedMarkdown
		dst.messageTimestamp = src.messageTimestamp
		dst.pkiEncrypted = src.pkiEncrypted
		dst.portNum = src.portNum
		dst.publicKey = src.publicKey
		dst.read = src.read
		dst.realACK = src.realACK
		dst.receivedACK = src.receivedACK
		dst.relayNode = src.relayNode
		dst.relays = src.relays
		dst.replyID = src.replyID
		dst.rssi = src.rssi
		dst.showTranslatedMessage = src.showTranslatedMessage
		dst.snr = src.snr
		dst.xeddsaSigned = src.xeddsaSigned
		dst.fromNum = src.fromNum
		dst.toNum = src.toNum
		dst.localNodeNum = src.localNodeNum
		dst.channelKey = src.channelKey
		dst.messageKey = src.messageKey
		dst.systemEvent = src.systemEvent
		dst.previousChannelKey = src.previousChannelKey
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: WaypointEntity) -> WaypointEntity {
		let dst = WaypointEntity()
		dst.created = src.created
		dst.createdBy = src.createdBy
		dst.expire = src.expire
		dst.icon = src.icon
		dst.id = src.id
		dst.lastUpdated = src.lastUpdated
		dst.lastUpdatedBy = src.lastUpdatedBy
		dst.latitudeI = src.latitudeI
		dst.locked = src.locked
		// Local-only flag: without it a restored private waypoint would be treated as a mesh
		// waypoint and could be overwritten by ingest.
		dst.isLocal = src.isLocal
		dst.longDescription = src.longDescription
		dst.longitudeI = src.longitudeI
		dst.name = src.name
		// Geofence settings are user-configured and not recoverable from the mesh.
		dst.geofenceRadius = src.geofenceRadius
		dst.hasBoundingBox = src.hasBoundingBox
		dst.boundingBoxLatitudeNorthI = src.boundingBoxLatitudeNorthI
		dst.boundingBoxLatitudeSouthI = src.boundingBoxLatitudeSouthI
		dst.boundingBoxLongitudeEastI = src.boundingBoxLongitudeEastI
		dst.boundingBoxLongitudeWestI = src.boundingBoxLongitudeWestI
		dst.notifyOnEnter = src.notifyOnEnter
		dst.notifyOnExit = src.notifyOnExit
		dst.notifyFavoritesOnly = src.notifyFavoritesOnly
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: TraceRouteEntity) -> TraceRouteEntity {
		let dst = TraceRouteEntity()
		dst.id = src.id
		dst.hasPositions = src.hasPositions
		dst.hopsBack = src.hopsBack
		dst.hopsTowards = src.hopsTowards
		dst.response = src.response
		dst.routeBackText = src.routeBackText
		dst.routeText = src.routeText
		dst.sent = src.sent
		dst.snr = src.snr
		dst.time = src.time
		dst.fromNum = src.fromNum
		dst.toNum = src.toNum
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: PaxCounterEntity) -> PaxCounterEntity {
		let dst = PaxCounterEntity()
		dst.ble = src.ble
		dst.time = src.time
		dst.uptime = src.uptime
		dst.wifi = src.wifi
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: NodeObservationEntity) -> NodeObservationEntity {
		let dst = NodeObservationEntity(radioNum: src.radioNum, nodeNum: src.nodeNum)
		dst.firstHeard = src.firstHeard
		dst.lastHeard = src.lastHeard
		dst.hopsAway = src.hopsAway
		dst.snr = src.snr
		dst.rssi = src.rssi
		dst.viaMqtt = src.viaMqtt
		dst.channel = src.channel
		dst.favorite = src.favorite
		dst.ignored = src.ignored
		dst.isKeyManuallyVerified = src.isKeyManuallyVerified
		dst.sessionPasskey = src.sessionPasskey
		dst.sessionExpiration = src.sessionExpiration
		return dst
	}

	/// Every stored field of `src` except its relationships, on a new, uninserted row.
	nonisolated static func copied(_ src: PacketReceptionEntity) -> PacketReceptionEntity {
		let dst = PacketReceptionEntity(radioNum: src.radioNum, fromNum: src.fromNum, packetId: src.packetId)
		dst.toNum = src.toNum
		dst.portNum = src.portNum
		dst.channel = src.channel
		dst.rxTime = src.rxTime
		dst.snr = src.snr
		dst.rssi = src.rssi
		dst.hopStart = src.hopStart
		dst.hopLimit = src.hopLimit
		dst.relayNode = src.relayNode
		dst.viaMqtt = src.viaMqtt
		return dst
	}
}
