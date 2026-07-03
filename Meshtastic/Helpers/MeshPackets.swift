//
//  MeshPackets.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/27/22.
//

import Foundation
@preconcurrency import SwiftData
import MeshtasticProtobufs
import SwiftUI
import RegexBuilder
import OSLog
#if canImport(ActivityKit)
import ActivityKit
#endif

// Simple extension to concisely pass values through a has_XXX boolean check
fileprivate extension Bool {
	func then<T>(_ value: T) -> T? {
		self ? value : nil
	}
}

func generateMessageMarkdown(message: String) -> String {
	guard !message.isEmoji() else { return message }
	let types: NSTextCheckingResult.CheckingType = [.address, .link, .phoneNumber]
	guard let detector = try? NSDataDetector(types: types.rawValue) else {
		return message
	}
	let matches = detector.matches(in: message, options: [], range: NSRange(location: 0, length: message.utf16.count))
	guard !matches.isEmpty else { return message }

	// Find all existing markdown link ranges [text](url) so we can skip URLs inside them
	let linkPattern = try? NSRegularExpression(pattern: "\\[[^\\]]+\\]\\([^)]+\\)")
	let existingLinkRanges: [NSRange] = linkPattern?.matches(in: message, range: NSRange(location: 0, length: message.utf16.count)).map { $0.range } ?? []

	var messageWithMarkdown = message
	// Process matches in reverse order so earlier ranges stay valid
	// after inserting markdown syntax at later positions.
	for match in matches.reversed() {
		guard let range = Range(match.range, in: messageWithMarkdown) else { continue }
		let matchedText = String(messageWithMarkdown[range])

		// Skip if this match overlaps with an existing markdown link
		let matchNSRange = match.range
		let isInsideExistingLink = existingLinkRanges.contains { linkRange in
			NSIntersectionRange(linkRange, matchNSRange).length > 0
		}
		if isInsideExistingLink { continue }

		let replacement: String
		if match.resultType == .address {
			let urlEncodedAddress = matchedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
			replacement = "[\(matchedText)](http://maps.apple.com/?address=\(urlEncodedAddress))"
		} else if match.resultType == .phoneNumber {
			replacement = "[\(matchedText)](tel:\(matchedText))"
		} else if match.resultType == .link {
			let absoluteUrl = match.url?.absoluteString ?? ""
			replacement = "[\(matchedText)](\(absoluteUrl))"
		} else {
			continue
		}
		messageWithMarkdown.replaceSubrange(range, with: replacement)
	}
	return messageWithMarkdown
}

@ModelActor
actor MeshPackets {
	private struct TelemetryPruneKey: Hashable {
		let nodeNum: Int64
		let metricsType: Int32
	}

	/// Always the current shared container. Computed (not cached) so that after a data clear
	/// recreates the container, the next `recreateShared()` rebuilds the actor on the new one
	/// rather than a stale, torn-down container. Only read on the main actor (recreateShared and
	/// the initial `_shared` are both reached from @MainActor code).
	private static var _container: ModelContainer {
		MainActor.assumeIsolated { PersistenceController.shared.container }
	}

	/// The current shared instance. Access via `MeshPackets.shared`.
	/// Periodically recreated to release accumulated ModelContext memory.
	nonisolated(unsafe) private static var _shared: MeshPackets = MeshPackets(modelContainer: _container)
	private static let _lock = NSLock()

	static var shared: MeshPackets {
		_lock.lock()
		defer { _lock.unlock() }
		return _shared
	}

	/// Discards the current actor and creates a fresh one with a new ModelContext.
	/// Call after DB retrieval completes or periodically to release accumulated memory.
	static func recreateShared() {
		_lock.lock()
		_shared = MeshPackets(modelContainer: _container)
		_lock.unlock()
		Logger.data.info("♻️ [MeshPackets] Recreated shared instance to release ModelContext memory")
	}

	// MARK: - Save Helpers

	/// Saves any pending changes in the model context. Call once at the end of each
	/// top-level packet handler to batch all mutations from a single packet into one write.
	func savePendingChanges(caller: String = #function) {
		guard modelContext.hasChanges else { return }
		do {
			try modelContext.save()
			Logger.data.debug("💾 [\(caller, privacy: .public)] Saved pending changes")
		} catch {
			Logger.data.error("💥 [\(caller, privacy: .public)] Error saving: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Debounced Save for High-Frequency Packets

	/// Timer task for debounced saves (position/telemetry).
	private var debounceSaveTask: Task<Void, Never>?
	/// Tracks when we last flushed debounced changes to enforce a maximum delay.
	private var lastDebouncedSaveTime: ContinuousClock.Instant = .now
	/// How long to wait after the last mutation before flushing.
	private static let debounceInterval: Duration = .seconds(2)
	/// Maximum wall-clock time between flushes, even if packets keep arriving.
	private static let maxDebounceDelay: Duration = .seconds(5)
	static let maxPositionHistoryPerNode = 5_000
	static let maxTelemetryPerType = 5_000
	static let maxTotalMessages = 50_000
	private static let positionPruneInterval = 128
	private static let telemetryPruneInterval = 128
	private static let messagePruneInterval = 256
	private var positionInsertsSincePrune: [Int64: Int] = [:]
	private var telemetryInsertsSincePrune: [TelemetryPruneKey: Int] = [:]
	private var messageInsertsSincePrune = 0

	/// Schedules a debounced save. Each call resets the 2-second timer. If packets
	/// keep arriving continuously, a save is forced every 5 seconds.
	/// Use for high-frequency packet types (position, telemetry) instead of `savePendingChanges`.
	func scheduleDebouncedSave() {
		debounceSaveTask?.cancel()
		let elapsed = ContinuousClock.now - lastDebouncedSaveTime
		if elapsed >= Self.maxDebounceDelay {
			savePendingChanges(caller: "debouncedFlush-maxDelay")
			lastDebouncedSaveTime = .now
			return
		}
		debounceSaveTask = Task {
			try? await Task.sleep(for: Self.debounceInterval)
			guard !Task.isCancelled else { return }
			self.savePendingChanges(caller: "debouncedFlush")
			self.lastDebouncedSaveTime = .now
		}
	}

	/// Immediately flushes any debounced saves. Call on disconnect or when entering background.
	func flushDebouncedSaves() {
		debounceSaveTask?.cancel()
		debounceSaveTask = nil
		savePendingChanges(caller: "flushDebouncedSaves")
		lastDebouncedSaveTime = .now
	}

	/// Last time the channel-unread badge count was recomputed (an O(unread) scan).
	private var lastChannelUnreadRecompute: ContinuousClock.Instant?
	/// Rate-limits the per-message channel-unread recompute to at most ~1/sec so a burst
	/// of incoming channel messages doesn't turn the badge update into quadratic work.
	func shouldRecomputeChannelUnread() -> Bool {
		let now = ContinuousClock.now
		if let last = lastChannelUnreadRecompute, now - last < .seconds(1) { return false }
		lastChannelUnreadRecompute = now
		return true
	}

	func shouldPrunePositionHistory(for nodeNum: Int64) -> Bool {
		let nextCount = (positionInsertsSincePrune[nodeNum] ?? 0) + 1
		if nextCount >= Self.positionPruneInterval {
			positionInsertsSincePrune[nodeNum] = 0
			return true
		}
		positionInsertsSincePrune[nodeNum] = nextCount
		return false
	}

	func shouldPruneTelemetryHistory(nodeNum: Int64, metricsType: Int32) -> Bool {
		let key = TelemetryPruneKey(nodeNum: nodeNum, metricsType: metricsType)
		let nextCount = (telemetryInsertsSincePrune[key] ?? 0) + 1
		if nextCount >= Self.telemetryPruneInterval {
			telemetryInsertsSincePrune[key] = 0
			return true
		}
		telemetryInsertsSincePrune[key] = nextCount
		return false
	}

	func shouldPruneMessageHistory() -> Bool {
		messageInsertsSincePrune += 1
		if messageInsertsSincePrune >= Self.messagePruneInterval {
			messageInsertsSincePrune = 0
			return true
		}
		return false
	}

	func localConfig (config: Config, nodeNum: Int64, nodeLongName: String) {
		switch config.payloadVariant {
		case .bluetooth:
			upsertBluetoothConfigPacket(config: config.bluetooth, nodeNum: nodeNum)
		case .device:
			upsertDeviceConfigPacket(config: config.device, nodeNum: nodeNum)
		case .display:
			upsertDisplayConfigPacket(config: config.display, nodeNum: nodeNum)
		case .lora:
			upsertLoRaConfigPacket(config: config.lora, nodeNum: nodeNum)
		case .network:
			upsertNetworkConfigPacket(config: config.network, nodeNum: nodeNum)
		case .position:
			upsertPositionConfigPacket(config: config.position, nodeNum: nodeNum)
		case .power:
			upsertPowerConfigPacket(config: config.power, nodeNum: nodeNum)
		case .security:
			upsertSecurityConfigPacket(config: config.security, nodeNum: nodeNum)
		default:
#if DEBUG
			Logger.services.error("⁉️ Unknown Config variant UNHANDLED \(config.payloadVariant.debugDescription, privacy: .public)")
#endif
		}
	}

	func moduleConfig (config: ModuleConfig, nodeNum: Int64, nodeLongName: String) {
		switch config.payloadVariant {
		case .ambientLighting:
			upsertAmbientLightingModuleConfigPacket(config: config.ambientLighting, nodeNum: nodeNum)
		case .audio:
			upsertAudioModuleConfigPacket(config: config.audio, nodeNum: nodeNum)
		case .cannedMessage:
			upsertCannedMessagesModuleConfigPacket(config: config.cannedMessage, nodeNum: nodeNum)
		case .detectionSensor:
			upsertDetectionSensorModuleConfigPacket(config: config.detectionSensor, nodeNum: nodeNum)
		case .externalNotification:
			upsertExternalNotificationModuleConfigPacket(config: config.externalNotification, nodeNum: nodeNum)
		case .mqtt:
			upsertMqttModuleConfigPacket(config: config.mqtt, nodeNum: nodeNum)
		case .neighborInfo:
			upsertNeighborInfoModuleConfigPacket(config: config.neighborInfo, nodeNum: nodeNum)
		case .paxcounter:
			upsertPaxCounterModuleConfigPacket(config: config.paxcounter, nodeNum: nodeNum)
		case .rangeTest:
			upsertRangeTestModuleConfigPacket(config: config.rangeTest, nodeNum: nodeNum)
		case .serial:
			upsertSerialModuleConfigPacket(config: config.serial, nodeNum: nodeNum)
		case .telemetry:
			upsertTelemetryModuleConfigPacket(config: config.telemetry, nodeNum: nodeNum)
		case .storeForward:
			upsertStoreForwardModuleConfigPacket(config: config.storeForward, nodeNum: nodeNum)
		case .statusmessage:
			upsertStatusMessageModuleConfigPacket(config: config.statusmessage, nodeNum: nodeNum)
		case .tak:
			upsertTAKModuleConfigPacket(config: config.tak, nodeNum: nodeNum)
		case .trafficManagement:
			upsertTrafficManagementModuleConfigPacket(config: config.trafficManagement, nodeNum: nodeNum)
		default:
#if DEBUG
			Logger.services.error("⁉️ Unknown Module Config variant UNHANDLED \(config.payloadVariant.debugDescription, privacy: .public)")
#endif
		}
	}

	func myInfoPacket (myInfo: MyNodeInfo, peripheralId: String) -> PersistentIdentifier? {
		let logString = String.localizedStringWithFormat("MyInfo received: %@".localized, String(myInfo.myNodeNum))
		Logger.admin.info("ℹ️ \(logString, privacy: .public)")
		
		let myNodeNum = Int64(myInfo.myNodeNum)
		let fetchDescriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == myNodeNum })

		do {
			let fetchedMyInfo = try modelContext.fetch(fetchDescriptor)
			// Not Found Insert
			if fetchedMyInfo.isEmpty {

				let myInfoEntity = MyInfoEntity()
				modelContext.insert(myInfoEntity)
				myInfoEntity.peripheralId = peripheralId
				myInfoEntity.myNodeNum = Int64(myInfo.myNodeNum)
				myInfoEntity.rebootCount = Int32(myInfo.rebootCount)
				myInfoEntity.deviceId = myInfo.deviceID
				if !myInfo.pioEnv.isEmpty {
					myInfoEntity.pioEnv = myInfo.pioEnv
				}
				Logger.data.info("💾 Saved a new myInfo for node: \(myInfo.myNodeNum.toHex(), privacy: .public)")
				savePendingChanges()
				return myInfoEntity.persistentModelID
			} else {

				fetchedMyInfo[0].peripheralId = peripheralId
				fetchedMyInfo[0].myNodeNum = Int64(myInfo.myNodeNum)
				fetchedMyInfo[0].rebootCount = Int32(myInfo.rebootCount)
				if !myInfo.pioEnv.isEmpty {
					fetchedMyInfo[0].pioEnv = myInfo.pioEnv
				}

				Logger.data.info("💾 Updated myInfo for node: \(myInfo.myNodeNum.toHex(), privacy: .public)")
				savePendingChanges()
				return fetchedMyInfo[0].persistentModelID
			}
		} catch {
			Logger.data.error("💥 Fetch MyInfo Error")
		}
		return nil
	}

	func channelPacket (channel: Channel, fromNum: Int64) {
		if channel.isInitialized && channel.hasSettings && channel.role != Channel.Role.disabled {
			let logString = String.localizedStringWithFormat("Channel received: %d %@".localized, channel.index, String(fromNum))
			Logger.admin.info("🎛️ \(logString, privacy: .public)")
			
			let fetchDescriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == fromNum })

			do {
				let fetchedMyInfo = try modelContext.fetch(fetchDescriptor)
				if fetchedMyInfo.count == 1 {
					let existing = fetchedMyInfo[0].channels.first(where: { $0.index == Int32(channel.index) })
					let newChannel: ChannelEntity
					if let existing {
						newChannel = existing
					} else {
						newChannel = ChannelEntity()
						modelContext.insert(newChannel)
						fetchedMyInfo[0].channels.append(newChannel)
					}
					newChannel.id = Int32(channel.index)
					newChannel.index = Int32(channel.index)
					newChannel.uplinkEnabled = channel.settings.uplinkEnabled
					newChannel.downlinkEnabled = channel.settings.downlinkEnabled
					newChannel.name = channel.settings.name
					newChannel.role = Int32(channel.role.rawValue)
					newChannel.psk = channel.settings.psk
					if channel.settings.hasModuleSettings {
						newChannel.positionPrecision = Int32(truncatingIfNeeded: channel.settings.moduleSettings.positionPrecision)
						newChannel.mute = channel.settings.moduleSettings.isMuted
					} else {
						// When moduleSettings is absent, use proto3 defaults (0/false)
						// rather than the entity default of 32, which would incorrectly
						// enable full-precision position sharing.
						newChannel.positionPrecision = 0
						newChannel.mute = false
					}
					savePendingChanges()
					Logger.data.info("💾 Updated MyInfo channel \(channel.index, privacy: .public) from Channel App Packet For: \(fetchedMyInfo[0].myNodeNum, privacy: .public)")
				} else if channel.role.rawValue > 0 {
					Logger.data.error("💥Trying to save a channel to a MyInfo that does not exist: \(fromNum.toHex(), privacy: .public)")
				}
			} catch {
				let nsError = error as NSError
				Logger.data.error("💥 Error Saving MyInfo Channel from ADMIN_APP \(nsError, privacy: .public)")
			}
		}
	}

	func deviceMetadataPacket (metadata: DeviceMetadata, fromNum: Int64, sessionPasskey: Data? = Data()) {
		if metadata.isInitialized {
			let logString = String.localizedStringWithFormat("Device Metadata received from: %@".localized, fromNum.toHex())
			Logger.admin.info("🏷️ \(logString, privacy: .public)")
			
			let fetchDescriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == fromNum })

			do {
				let fetchedNode = try modelContext.fetch(fetchDescriptor)
				let newMetadata = DeviceMetadataEntity()
				modelContext.insert(newMetadata)
				newMetadata.time = Date()
				newMetadata.deviceStateVersion = Int32(metadata.deviceStateVersion)
				newMetadata.canShutdown = metadata.canShutdown
				newMetadata.hasWifi = metadata.hasWifi_p
				newMetadata.hasBluetooth = metadata.hasBluetooth_p
				newMetadata.hasEthernet	= metadata.hasEthernet_p
				newMetadata.role = Int32(metadata.role.rawValue)
				newMetadata.positionFlags = Int32(truncatingIfNeeded: metadata.positionFlags)
				newMetadata.excludedModules = Int32(truncatingIfNeeded: metadata.excludedModules)
				// Swift does strings weird, this does work to get the version without the github hash
				let lastDotIndex = metadata.firmwareVersion.lastIndex(of: ".")
				var version = metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: metadata.firmwareVersion))]
				version = version.dropLast()
				newMetadata.firmwareVersion = String(version)
				if fetchedNode.count > 0 {
					fetchedNode[0].metadata = newMetadata
					if sessionPasskey?.count != 0 {
						fetchedNode[0].sessionPasskey = sessionPasskey
						fetchedNode[0].sessionExpiration = Date().addingTimeInterval(300)
					}
				} else {
					if fromNum > 0 {
						let newNode = findOrCreateNode(num: Int64(fromNum), context: modelContext)
						newNode.metadata = newMetadata
					}
				}
				savePendingChanges()
				Logger.data.info("💾 Updated Device Metadata from Admin App Packet For: \(fromNum.toHex(), privacy: .public)")
			} catch {
				let nsError = error as NSError
				Logger.data.error("Error Saving MyInfo Channel from ADMIN_APP \(nsError, privacy: .public)")
			}
		}
	}

	func nodeInfoPacket (nodeInfo: NodeInfo, channel: UInt32, deferSave: Bool = false) -> PersistentIdentifier? {
		// This path handles the connected device's local node-DB dump during wantConfig
		// (FromRadio.nodeInfo), not packets that crossed the mesh — log it as admin/setup.
		// Over-the-air NodeInfo arrives via upsertNodeInfoPacket and stays on .mesh.
		let logString = String.localizedStringWithFormat("📟 [NodeInfo] received for: %@".localized, String(nodeInfo.num))
		Logger.admin.info("📟 \(logString, privacy: .public)")

		guard nodeInfo.num > 0 else { return nil }

		let nodeNum = Int64(nodeInfo.num)
		let fetchDescriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })

		do {
			let fetchedNode = try modelContext.fetch(fetchDescriptor)
			// Not Found Insert
			if fetchedNode.isEmpty && nodeInfo.num > 0 {

				let newNode = NodeInfoEntity()
					modelContext.insert(newNode)
					newNode.id = Int64(nodeInfo.num)
					newNode.num = Int64(nodeInfo.num)
					newNode.channel = Int32(nodeInfo.channel)
					newNode.favorite = nodeInfo.isFavorite
					newNode.ignored = nodeInfo.isIgnored
					newNode.hopsAway = Int32(nodeInfo.hopsAway)
					newNode.hasXeddsaSigned = nodeInfo.hasXeddsaSigned_p

					if nodeInfo.hasDeviceMetrics {
						let telemetry = TelemetryEntity()
						modelContext.insert(telemetry)
						telemetry.batteryLevel = Int32(truncatingIfNeeded: nodeInfo.deviceMetrics.batteryLevel)
						telemetry.voltage = nodeInfo.deviceMetrics.voltage
						telemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
						telemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx
						telemetry.nodeTelemetry = newNode
					}
					if nodeInfo.lastHeard > 0 {
						newNode.firstHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
						newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
					} else {
						newNode.firstHeard = Date()
						newNode.lastHeard = Date()
					}
					newNode.snr = nodeInfo.snr
					if nodeInfo.hasUser {

						let newUser = UserEntity()
						modelContext.insert(newUser)
						newUser.userId = nodeInfo.num.toHex()
						newUser.num = Int64(nodeInfo.num)
						newUser.longName = nodeInfo.user.longName
						newUser.shortName = nodeInfo.user.shortName
						newUser.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
						newUser.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)
						let hwModelValue = Int64(newUser.hwModelId)
						let hwDescriptor = FetchDescriptor<DeviceHardwareEntity>(
							predicate: #Predicate { $0.hwModel == hwModelValue }
						)
						if let hardwareEntity = try? modelContext.fetch(hwDescriptor).first {
							newUser.hwDisplayName = hardwareEntity.displayName
						}
						newUser.isLicensed = nodeInfo.user.isLicensed
						newUser.role = Int32(nodeInfo.user.role.rawValue)
						if !nodeInfo.user.publicKey.isEmpty {
							newUser.pkiEncrypted = true
							newUser.publicKey = nodeInfo.user.publicKey
						}
						/// For nodes that have the optional isUnmessagable boolean use that, otherwise excluded roles that are unmessagable by default
						if nodeInfo.user.hasIsUnmessagable {
							newUser.unmessagable = nodeInfo.user.isUnmessagable
						} else {
							let roles = [2, 4, 5, 6, 7, 10, 11]
							let containsRole = roles.contains(Int(newUser.role))
							if containsRole {
								newUser.unmessagable = true
							} else {
								newUser.unmessagable = false
							}}
						newNode.user = newUser
					} else if nodeInfo.num > Constants.minimumNodeNum {
						do {
							let newUser = try createUser(num: Int64(nodeInfo.num), context: modelContext)
							newNode.user = newUser
						} catch PersistenceError.invalidInput(let message) {
							Logger.data.error("Error Creating a new UserEntity (Invalid Input) from node number: \(nodeInfo.num, privacy: .public) Error:  \(message, privacy: .public)")
						} catch {
							Logger.data.error("Error Creating a new UserEntity from node number: \(nodeInfo.num, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
						}
					}

					if nodeInfo.position.hasValidCoordinates {
						let position = PositionEntity()
						modelContext.insert(position)
						position.latest = true
						position.seqNo = Int32(nodeInfo.position.seqNumber)
						position.latitudeI = nodeInfo.position.latitudeI
						position.longitudeI = nodeInfo.position.longitudeI
						position.altitude = nodeInfo.position.altitude
						position.satsInView = Int32(nodeInfo.position.satsInView)
						position.speed = Int32(nodeInfo.position.groundSpeed)
						position.heading = Int32(nodeInfo.position.groundTrack)
						position.time = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.position.time)))
						position.nodePosition = newNode
						newNode.latestPositionCache = position
					}

					// Look for a MyInfo
					let myInfoNodeNum = Int64(nodeInfo.num)
					let fetchMyInfoDescriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == myInfoNodeNum })

					do {
						let fetchedMyInfo = try modelContext.fetch(fetchMyInfoDescriptor)
						if fetchedMyInfo.count > 0 {
							newNode.myInfo = fetchedMyInfo[0]
						}
						if !deferSave {
							savePendingChanges()
							Logger.data.debug("💾 Saved a new Node Info For: \(String(nodeInfo.num), privacy: .public)")
						}
						return newNode.persistentModelID
					} catch {
						Logger.data.error("Fetch MyInfo Error")
					}
				} else if nodeInfo.num > 0 {

					fetchedNode[0].id = Int64(nodeInfo.num)
					fetchedNode[0].num = Int64(nodeInfo.num)
					if nodeInfo.lastHeard > 0 {
						let candidate = Date(timeIntervalSince1970: TimeInterval(nodeInfo.lastHeard))
						if fetchedNode[0].lastHeard == nil || candidate > fetchedNode[0].lastHeard! {
							fetchedNode[0].lastHeard = candidate
						}
					}
					fetchedNode[0].snr = nodeInfo.snr
					fetchedNode[0].channel = Int32(nodeInfo.channel)
					fetchedNode[0].favorite = nodeInfo.isFavorite
					fetchedNode[0].ignored = nodeInfo.isIgnored
					fetchedNode[0].hopsAway = Int32(nodeInfo.hopsAway)
					// has_xeddsa_signed means the node has signed ≥1 verified broadcast and persists; latch it
					// so a later NodeInfo that omits the bit doesn't downgrade a node we've seen sign.
					fetchedNode[0].hasXeddsaSigned = fetchedNode[0].hasXeddsaSigned || nodeInfo.hasXeddsaSigned_p

					if nodeInfo.hasUser {
						if fetchedNode[0].user == nil {
							let newUserEntity = UserEntity()
							modelContext.insert(newUserEntity)
							fetchedNode[0].user = newUserEntity
						}
						// Set the public key for a user if it is empty, don't update
						if fetchedNode[0].user?.publicKey == nil && !nodeInfo.user.publicKey.isEmpty {
							fetchedNode[0].user?.pkiEncrypted = true
							fetchedNode[0].user?.publicKey = nodeInfo.user.publicKey
						}
						fetchedNode[0].user?.userId = nodeInfo.num.toHex()
						fetchedNode[0].user?.num = Int64(nodeInfo.num)
						fetchedNode[0].user?.numString = String(nodeInfo.num)
						fetchedNode[0].user?.longName = nodeInfo.user.longName
						fetchedNode[0].user?.shortName = nodeInfo.user.shortName
						fetchedNode[0].user?.isLicensed = nodeInfo.user.isLicensed
						fetchedNode[0].user?.role = Int32(nodeInfo.user.role.rawValue)
						fetchedNode[0].user?.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
						fetchedNode[0].user?.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)
						/// For nodes that have the optional isUnmessagable boolean use that, otherwise excluded roles that are unmessagable by default
						if nodeInfo.user.hasIsUnmessagable {
							fetchedNode[0].user?.unmessagable = nodeInfo.user.isUnmessagable
						} else {
							let roles = [-1, 2, 4, 5, 6, 7, 10, 11]
							let containsRole = roles.contains(Int(fetchedNode[0].user?.role ?? -1))
							if containsRole {
								fetchedNode[0].user?.unmessagable = true
							} else {
								fetchedNode[0].user?.unmessagable = false
							}
						}
						if let user = fetchedNode.first?.user {
							let hwModelValue2 = Int64(user.hwModelId)
							let hwDescriptor2 = FetchDescriptor<DeviceHardwareEntity>(
								predicate: #Predicate { $0.hwModel == hwModelValue2 }
							)
							if let hardwareEntity = try? modelContext.fetch(hwDescriptor2).first {
								user.hwDisplayName = hardwareEntity.displayName
							}
						}
					} else {
						if fetchedNode[0].user == nil && nodeInfo.num > Constants.minimumNodeNum {
							do {
								let newUser = try createUser(num: Int64(nodeInfo.num), context: modelContext)
								fetchedNode[0].user = newUser
							} catch PersistenceError.invalidInput(let message) {
								Logger.data.error("Error Creating a new UserEntity on an existing node (Invalid Input) from node number: \(nodeInfo.num, privacy: .public) Error:  \(message, privacy: .public)")
							} catch {
								Logger.data.error("Error Creating a new UserEntity on an existing node from node number: \(nodeInfo.num, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
							}
						}
					}

					if nodeInfo.hasDeviceMetrics {

						let newTelemetry = TelemetryEntity()
						modelContext.insert(newTelemetry)
						newTelemetry.batteryLevel = Int32(truncatingIfNeeded: nodeInfo.deviceMetrics.batteryLevel)
						newTelemetry.voltage = nodeInfo.deviceMetrics.voltage
						newTelemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
						newTelemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx
						newTelemetry.nodeTelemetry = fetchedNode[0]
					}

					if nodeInfo.hasPosition {

						if nodeInfo.position.hasValidCoordinates {

							let position = PositionEntity()
							modelContext.insert(position)
							position.latitudeI = nodeInfo.position.latitudeI
							position.longitudeI = nodeInfo.position.longitudeI
							position.altitude = nodeInfo.position.altitude
							position.satsInView = Int32(nodeInfo.position.satsInView)
							position.time = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.position.time)))
							position.nodePosition = fetchedNode[0]
						}

					}

					// Look for a MyInfo
					let myInfoNodeNum2 = Int64(nodeInfo.num)
					let fetchMyInfoDescriptor2 = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == myInfoNodeNum2 })

					do {
						let fetchedMyInfo = try modelContext.fetch(fetchMyInfoDescriptor2)
						if fetchedMyInfo.count > 0 {
							fetchedNode[0].myInfo = fetchedMyInfo[0]
						}
						if !deferSave {
							savePendingChanges()
							Logger.data.debug("💾 [Node Info] saved for \(nodeInfo.num.toHex(), privacy: .public)")
						}
						return fetchedNode[0].persistentModelID
					} catch {
						Logger.data.error("💥 Fetch MyInfo Error")
					}
				}
		} catch {
			Logger.data.error("💥 Fetch NodeInfoEntity Error")
		}
		return nil
	}

	func adminAppPacket (packet: MeshPacket) {
		if let adminMessage = try? AdminMessage(serializedBytes: packet.decoded.payload) {

			if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getCannedMessageModuleMessagesResponse(adminMessage.getCannedMessageModuleMessagesResponse) {

				if let cmmc = try? CannedMessageModuleConfig(serializedBytes: packet.decoded.payload) {
					let logString = String.localizedStringWithFormat("Canned Messages Messages Received For: %@".localized, packet.from.toHex())
					Logger.admin.info("🥫 \(logString, privacy: .public)")
					
					let packetFrom = Int64(packet.from)
					let fetchDescriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == packetFrom })

					do {
						let fetchedNode = try modelContext.fetch(fetchDescriptor)
						if fetchedNode.count == 1 {
							let messages =  String(cmmc.textFormatString())
								.replacingOccurrences(of: "11: ", with: "")
								.replacingOccurrences(of: "\"", with: "")
								.trimmingCharacters(in: .whitespacesAndNewlines)
								.components(separatedBy: "\n").first ?? ""
							fetchedNode[0].cannedMessageConfig?.messages = messages
							savePendingChanges()
							Logger.data.info("💾 Updated Canned Messages Messages For: \(fetchedNode.first?.num.toHex() ?? "Unknown".localized, privacy: .public)")
						}
					} catch {
						Logger.data.error("💥 Error Deserializing ADMIN_APP packet.")
					}
				}
			} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getChannelResponse(adminMessage.getChannelResponse) {
				channelPacket(channel: adminMessage.getChannelResponse, fromNum: Int64(packet.from))
			} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getDeviceMetadataResponse(adminMessage.getDeviceMetadataResponse) {
				deviceMetadataPacket(metadata: adminMessage.getDeviceMetadataResponse, fromNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
			} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getConfigResponse(adminMessage.getConfigResponse) {
				let config = adminMessage.getConfigResponse
				if config.payloadVariant == Config.OneOf_PayloadVariant.bluetooth(config.bluetooth) {
					upsertBluetoothConfigPacket(config: config.bluetooth, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				} else if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
					upsertDeviceConfigPacket(config: config.device, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				} else if config.payloadVariant == Config.OneOf_PayloadVariant.display(config.display) {
					self.upsertDisplayConfigPacket(config: config.display, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				} else if config.payloadVariant == Config.OneOf_PayloadVariant.lora(config.lora) {
					self.upsertLoRaConfigPacket(config: config.lora, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				} else if config.payloadVariant == Config.OneOf_PayloadVariant.network(config.network) {
					self.upsertNetworkConfigPacket(config: config.network, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				} else if config.payloadVariant == Config.OneOf_PayloadVariant.position(config.position) {
					self.upsertPositionConfigPacket(config: config.position, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				} else if config.payloadVariant == Config.OneOf_PayloadVariant.power(config.power) {
					self.upsertPowerConfigPacket(config: config.power, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				} else if config.payloadVariant == Config.OneOf_PayloadVariant.security(config.security) {
					self.upsertSecurityConfigPacket(config: config.security, nodeNum: Int64(packet.from), sessionPasskey: adminMessage.sessionPasskey)
				}
			} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getModuleConfigResponse(adminMessage.getModuleConfigResponse) {
				let moduleConfig = adminMessage.getModuleConfigResponse
				if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.ambientLighting(moduleConfig.ambientLighting) {
					self.upsertAmbientLightingModuleConfigPacket(config: moduleConfig.ambientLighting, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.audio(moduleConfig.audio) {
					self.upsertAudioModuleConfigPacket(config: moduleConfig.audio, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(moduleConfig.cannedMessage) {
					self.upsertCannedMessagesModuleConfigPacket(config: moduleConfig.cannedMessage, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.detectionSensor(moduleConfig.detectionSensor) {
					self.upsertDetectionSensorModuleConfigPacket(config: moduleConfig.detectionSensor, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.externalNotification(moduleConfig.externalNotification) {
					self.upsertExternalNotificationModuleConfigPacket(config: moduleConfig.externalNotification, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.mqtt(moduleConfig.mqtt) {
					self.upsertMqttModuleConfigPacket(config: moduleConfig.mqtt, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.rangeTest(moduleConfig.rangeTest) {
					self.upsertRangeTestModuleConfigPacket(config: moduleConfig.rangeTest, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.serial(moduleConfig.serial) {
					self.upsertSerialModuleConfigPacket(config: moduleConfig.serial, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.storeForward(moduleConfig.storeForward) {
					self.upsertStoreForwardModuleConfigPacket(config: moduleConfig.storeForward, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.telemetry(moduleConfig.telemetry) {
					self.upsertTelemetryModuleConfigPacket(config: moduleConfig.telemetry, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.tak(moduleConfig.tak) {
					self.upsertTAKModuleConfigPacket(config: moduleConfig.tak, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.statusmessage(moduleConfig.statusmessage) {
					self.upsertStatusMessageModuleConfigPacket(config: moduleConfig.statusmessage, nodeNum: Int64(packet.from))
				} else if moduleConfig.payloadVariant == ModuleConfig.OneOf_PayloadVariant.trafficManagement(moduleConfig.trafficManagement) {
					self.upsertTrafficManagementModuleConfigPacket(config: moduleConfig.trafficManagement, nodeNum: Int64(packet.from))
				}
			} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getRingtoneResponse(adminMessage.getRingtoneResponse) {
				if let rt = try? RTTTLConfig(serializedBytes: packet.decoded.payload) {
					self.upsertRtttlConfigPacket(ringtone: rt.ringtone, nodeNum: Int64(packet.from))
				}
			} else {
				Logger.admin.error("🕸️ MESH PACKET received Admin App UNHANDLED \((try? packet.decoded.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
			}
			// Save an ack for the admin message log for each admin message response received as we stopped sending acks if there is also a response to reduce airtime.
			self.adminResponseAck(packet: packet)
		}
	}

	private func adminResponseAck (packet: MeshPacket) {
		let requestID = Int64(packet.decoded.requestID)
		let fetchDescriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == requestID })
		do {
			let fetchedMessage = try modelContext.fetch(fetchDescriptor)
			if fetchedMessage.count > 0 {
				fetchedMessage[0].ackTimestamp = Int32(Date().timeIntervalSince1970)
				fetchedMessage[0].ackError = Int32(RoutingError.none.rawValue)
				fetchedMessage[0].receivedACK = true
				fetchedMessage[0].realACK = true
				fetchedMessage[0].relayNode = Int64(packet.relayNode)
				fetchedMessage[0].ackSNR = packet.rxSnr

				savePendingChanges()
			}
		} catch {
			Logger.data.error("Failed to fetch admin message by requestID: \(error.localizedDescription, privacy: .public)")
		}
	}

	func paxCounterPacket (packet: MeshPacket) {
		let paxDetail = (try? Paxcount(serializedBytes: packet.decoded.payload)).map { " — \($0.wifi) wifi \($0.ble) ble" } ?? ""
		Logger.mesh.info("[PAX Counter] packet received from \(packet.from.toHex(), privacy: .public)\(paxDetail, privacy: .public)")

		let packetFrom = Int64(packet.from)
		var fetchDescriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == packetFrom })
		fetchDescriptor.fetchLimit = 1

		do {
			let fetchedNode = try modelContext.fetch(fetchDescriptor)

			if let paxMessage = try? Paxcount(serializedBytes: packet.decoded.payload) {

				let newPax = PaxCounterEntity()
				modelContext.insert(newPax)
				newPax.ble = Int32(truncatingIfNeeded: paxMessage.ble)
				newPax.wifi = Int32(truncatingIfNeeded: paxMessage.wifi)
				newPax.uptime = Int32(truncatingIfNeeded: paxMessage.uptime)
				newPax.time = Date()

				if fetchedNode.count > 0 {
					newPax.paxNode = fetchedNode[0]
					scheduleDebouncedSave()
				} else {
					Logger.data.info("Node Info Not Found")
				}
			}
		} catch {

		}
	}

	func routingPacket (packet: MeshPacket, connectedNodeNum: Int64) {
		if let routingMessage = try? Routing(serializedBytes: packet.decoded.payload) {

			let routingError = RoutingError(rawValue: routingMessage.errorReason.rawValue)

			let routingErrorString = routingError?.display ?? "Unknown".localized
			let logString = String.localizedStringWithFormat("Routing received for RequestID: %@ Ack Status: %@".localized, String(packet.decoded.requestID), routingErrorString)
			Logger.mesh.info("🕸️ \(logString, privacy: .public)")

			let requestID = Int64(packet.decoded.requestID)
			let fetchDescriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == requestID })

			do {
				let fetchedMessage = try modelContext.fetch(fetchDescriptor)
				if fetchedMessage.count > 0 {
					if fetchedMessage[0].toUser != nil {
						// Real ACK from DM Recipient
						if packet.to != packet.from {
							fetchedMessage[0].realACK = true
						}
					}
					fetchedMessage[0].relayNode = Int64(packet.relayNode)
					fetchedMessage[0].ackError = Int32(routingMessage.errorReason.rawValue)
					if routingMessage.errorReason == Routing.Error.none {
						fetchedMessage[0].receivedACK = true
						fetchedMessage[0].relays += 1
					}

					fetchedMessage[0].ackSNR = packet.rxSnr
					if packet.rxTime > 0 {
						fetchedMessage[0].ackTimestamp = Int32(truncatingIfNeeded: packet.rxTime)
					} else {
						fetchedMessage[0].ackTimestamp = Int32(Date().timeIntervalSince1970)
					}

				} else {
					return
				}
				scheduleDebouncedSave()
				Logger.data.debug("💾 ACK buffered for Message: \(packet.decoded.requestID, privacy: .public)")
			} catch {
				let nsError = error as NSError
				Logger.data.error("Error Saving ACK for message: \(packet.id, privacy: .public) Error: \(nsError, privacy: .public)")
			}
		}
	}

	/// Compact, human-readable summary of a Telemetry packet for the mesh log line, e.g.
	/// " — device 87% 4.05V ch 12.3% air 3.1%" or " — env 23.5°C 45% 1013hPa". Reads the salient
	/// metrics per variant (not raw JSON); returns "" for unhandled variants.
	private func telemetryLogDetails(_ telemetry: Telemetry) -> String {
		var parts: [String] = []
		switch telemetry.variant {
		case .deviceMetrics(let m)?:
			parts.append("device")
			if m.hasBatteryLevel { parts.append("\(m.batteryLevel)%") }
			if m.hasVoltage { parts.append(String(format: "%.2fV", m.voltage)) }
			if m.hasChannelUtilization { parts.append(String(format: "ch %.1f%%", m.channelUtilization)) }
			if m.hasAirUtilTx { parts.append(String(format: "air %.1f%%", m.airUtilTx)) }
		case .environmentMetrics(let m)?:
			parts.append("env")
			if m.hasTemperature { parts.append(String(format: "%.1f°C", m.temperature)) }
			if m.hasRelativeHumidity { parts.append(String(format: "%.0f%%", m.relativeHumidity)) }
			if m.hasBarometricPressure { parts.append(String(format: "%.0fhPa", m.barometricPressure)) }
		case .powerMetrics(let m)?:
			parts.append("power")
			if m.hasCh1Voltage { parts.append(String(format: "ch1 %.2fV", m.ch1Voltage)) }
			if m.hasCh2Voltage { parts.append(String(format: "ch2 %.2fV", m.ch2Voltage)) }
			if m.hasCh3Voltage { parts.append(String(format: "ch3 %.2fV", m.ch3Voltage)) }
		case .localStats(let m)?:
			parts.append("stats")
			parts.append("\(m.numOnlineNodes)/\(m.numTotalNodes) nodes")
		default:
			return ""
		}
		return " — " + parts.joined(separator: " ")
	}

	/// First non-zero proto epoch (seconds since 1970) from `candidates`, as a `Date`; falls back to
	/// now when none are set. Remote nodes without an RTC/GPS report 0, which would otherwise store as
	/// 1970 and be hidden by the node detail's "latest" sort and the 7-day chart window — so callers
	/// pass the sensor's self-reported time first, then `packet.rxTime`, to anchor on the best clock
	/// available.
	private func resolveTimestamp(_ candidates: UInt32...) -> Date {
		for seconds in candidates where seconds > 0 {
			return Date(timeIntervalSince1970: TimeInterval(seconds))
		}
		return Date()
	}

	func telemetryPacket(packet: MeshPacket, connectedNode: Int64) {
		if let telemetryMessage = try? Telemetry(serializedBytes: packet.decoded.payload) {
			if telemetryMessage.variant != Telemetry.OneOf_Variant.deviceMetrics(telemetryMessage.deviceMetrics) && telemetryMessage.variant != Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) && telemetryMessage.variant != Telemetry.OneOf_Variant.localStats(telemetryMessage.localStats) && telemetryMessage.variant != Telemetry.OneOf_Variant.powerMetrics(telemetryMessage.powerMetrics) {
				/// Other unhandled telemetry packets
				return
			}
			// Mesh-category audit (spec 012): telemetry received over the air from a
			// remote node is genuine mesh traffic and belongs in the Packet Stream,
			// consistent with text/position/nodeinfo. The connected node's own
			// localStats (from == connectedNode) is local, not OTA, so it stays on
			// .data/.statistics below and out of the Mesh category.
			if connectedNode != Int64(packet.from) {
				Logger.mesh.info("📈 [Telemetry] packet received from \(packet.from.toHex(), privacy: .public)\(self.telemetryLogDetails(telemetryMessage), privacy: .public)")
			}
			let packetFrom = Int64(packet.from)
			// packet.from == 0 is not a real node, so there is nothing to attribute telemetry to.
			guard packetFrom > 0 else { return }
			// Telemetry is genuine RF contact with packet.from. Like deviceMetadataPacket /
			// textMessageAppPacket, ensure a NodeInfoEntity exists before storing so telemetry that
			// arrives before the node's NodeInfo / nodeDB entry is not dropped as an orphan row
			// (nodeTelemetry == nil) that the UI can never query. `num` is @Attribute(.unique), so this
			// returns the existing node or a minimal stub that a later NodeInfo packet enriches.
			let node = findOrCreateNode(num: packetFrom, context: modelContext)
			let telemetry = TelemetryEntity()
			modelContext.insert(telemetry)
			/// Currently only Device Metrics and Environment Telemetry are supported in the app
			if telemetryMessage.variant == Telemetry.OneOf_Variant.deviceMetrics(telemetryMessage.deviceMetrics) {
				// Device Metrics
				Logger.data.debug("📈 [Telemetry] Device Metrics Received for Node: \(packet.from.toHex(), privacy: .public)")
				telemetry.airUtilTx = telemetryMessage.deviceMetrics.hasAirUtilTx.then(telemetryMessage.deviceMetrics.airUtilTx)
				telemetry.channelUtilization = telemetryMessage.deviceMetrics.hasChannelUtilization.then(telemetryMessage.deviceMetrics.channelUtilization)
				telemetry.batteryLevel = telemetryMessage.deviceMetrics.hasBatteryLevel.then(Int32(truncatingIfNeeded: telemetryMessage.deviceMetrics.batteryLevel))
				telemetry.voltage = telemetryMessage.deviceMetrics.hasVoltage.then(telemetryMessage.deviceMetrics.voltage)
				telemetry.uptimeSeconds = telemetryMessage.deviceMetrics.hasUptimeSeconds.then(Int32(truncatingIfNeeded: telemetryMessage.deviceMetrics.uptimeSeconds))
				telemetry.metricsType = 0
				Logger.statistics.debug("📈 [Mesh Statistics] Channel Utilization: \(telemetryMessage.deviceMetrics.channelUtilization, privacy: .public) Airtime: \(telemetryMessage.deviceMetrics.airUtilTx, privacy: .public) for Node: \(packet.from.toHex(), privacy: .public)")
			} else if telemetryMessage.variant == Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) {
				// Environment Metrics
				Logger.data.debug("📈 [Telemetry] Environment Metrics Received for Node: \(packet.from.toHex(), privacy: .public)")
				telemetry.barometricPressure = telemetryMessage.environmentMetrics.hasBarometricPressure.then(telemetryMessage.environmentMetrics.barometricPressure)
				telemetry.iaq = telemetryMessage.environmentMetrics.hasIaq.then(Int32(truncatingIfNeeded: telemetryMessage.environmentMetrics.iaq))
				telemetry.gasResistance = telemetryMessage.environmentMetrics.hasGasResistance.then(telemetryMessage.environmentMetrics.gasResistance)
				telemetry.relativeHumidity = telemetryMessage.environmentMetrics.hasRelativeHumidity.then(telemetryMessage.environmentMetrics.relativeHumidity)
				telemetry.temperature = telemetryMessage.environmentMetrics.hasTemperature.then(telemetryMessage.environmentMetrics.temperature)
				telemetry.current = telemetryMessage.environmentMetrics.hasCurrent.then(telemetryMessage.environmentMetrics.current)
				telemetry.voltage = telemetryMessage.environmentMetrics.hasVoltage.then(telemetryMessage.environmentMetrics.voltage)
				telemetry.weight = telemetryMessage.environmentMetrics.hasWeight.then(telemetryMessage.environmentMetrics.weight)
				telemetry.distance = telemetryMessage.environmentMetrics.hasDistance.then(telemetryMessage.environmentMetrics.distance)
				telemetry.windSpeed = telemetryMessage.environmentMetrics.hasWindSpeed.then(telemetryMessage.environmentMetrics.windSpeed)
				telemetry.windGust = telemetryMessage.environmentMetrics.hasWindGust.then(telemetryMessage.environmentMetrics.windGust)
				telemetry.windLull = telemetryMessage.environmentMetrics.hasWindLull.then(telemetryMessage.environmentMetrics.windLull)
				telemetry.windDirection = telemetryMessage.environmentMetrics.hasWindDirection.then(Int32(truncatingIfNeeded: telemetryMessage.environmentMetrics.windDirection))
				telemetry.irLux = telemetryMessage.environmentMetrics.hasIrLux.then(telemetryMessage.environmentMetrics.irLux)
				telemetry.lux = telemetryMessage.environmentMetrics.hasLux.then(telemetryMessage.environmentMetrics.lux)
				telemetry.whiteLux = telemetryMessage.environmentMetrics.hasWhiteLux.then(telemetryMessage.environmentMetrics.whiteLux)
				telemetry.uvLux = telemetryMessage.environmentMetrics.hasUvLux.then(telemetryMessage.environmentMetrics.uvLux)
				telemetry.radiation = telemetryMessage.environmentMetrics.hasRadiation.then(telemetryMessage.environmentMetrics.radiation)
				telemetry.rainfall1H = telemetryMessage.environmentMetrics.hasRainfall1H.then(telemetryMessage.environmentMetrics.rainfall1H)
				telemetry.rainfall24H = telemetryMessage.environmentMetrics.hasRainfall24H.then(telemetryMessage.environmentMetrics.rainfall24H)
				telemetry.soilTemperature = telemetryMessage.environmentMetrics.hasSoilTemperature.then(telemetryMessage.environmentMetrics.soilTemperature)
				telemetry.soilMoisture = telemetryMessage.environmentMetrics.hasSoilMoisture.then(telemetryMessage.environmentMetrics.soilMoisture)
				telemetry.metricsType = 1
			} else if telemetryMessage.variant == Telemetry.OneOf_Variant.localStats(telemetryMessage.localStats) {
				// Local Stats for Live activity
				telemetry.uptimeSeconds = Int32(truncatingIfNeeded: telemetryMessage.localStats.uptimeSeconds)
				telemetry.channelUtilization = telemetryMessage.localStats.channelUtilization
				telemetry.airUtilTx = telemetryMessage.localStats.airUtilTx
				telemetry.numPacketsTx = Int32(truncatingIfNeeded: telemetryMessage.localStats.numPacketsTx)
				telemetry.numPacketsRx = Int32(truncatingIfNeeded: telemetryMessage.localStats.numPacketsRx)
				telemetry.numPacketsRxBad = Int32(truncatingIfNeeded: telemetryMessage.localStats.numPacketsRxBad)
				telemetry.numRxDupe = Int32(truncatingIfNeeded: telemetryMessage.localStats.numRxDupe)
				telemetry.numTxRelay = Int32(truncatingIfNeeded: telemetryMessage.localStats.numTxRelay)
				telemetry.numTxRelayCanceled = Int32(truncatingIfNeeded: telemetryMessage.localStats.numTxRelayCanceled)
				telemetry.numOnlineNodes = Int32(truncatingIfNeeded: telemetryMessage.localStats.numOnlineNodes)
				telemetry.numTotalNodes = Int32(truncatingIfNeeded: telemetryMessage.localStats.numTotalNodes)
				// `noise_floor` is a plain proto3 scalar (not `optional`), so it has no
				// presence tracking — firmware that doesn't report it is indistinguishable
				// from a literal 0. Real LoRa noise floors are always strongly negative, so
				// we treat 0 as "not available" (nil). If true nil-vs-0 is ever needed, make
				// the field `optional` upstream and use `hasNoiseFloor`.
				telemetry.noiseFloor = telemetryMessage.localStats.noiseFloor != 0 ? telemetryMessage.localStats.noiseFloor : nil
				telemetry.metricsType = 4
				Logger.statistics.debug("📈 [Mesh Statistics] Channel Utilization: \(telemetryMessage.localStats.channelUtilization, privacy: .public) Airtime: \(telemetryMessage.localStats.airUtilTx, privacy: .public) Packets Sent: \(telemetryMessage.localStats.numPacketsTx, privacy: .public) Packets Received: \(telemetryMessage.localStats.numPacketsRx, privacy: .public) Bad Packets Received: \(telemetryMessage.localStats.numPacketsRxBad, privacy: .public) Noise Floor: \(telemetryMessage.localStats.noiseFloor, privacy: .public) Nodes Online: \(telemetryMessage.localStats.numOnlineNodes, privacy: .public) of \(telemetryMessage.localStats.numTotalNodes, privacy: .public) nodes for Node: \(packet.from.toHex(), privacy: .public)")
			} else if telemetryMessage.variant == Telemetry.OneOf_Variant.powerMetrics(telemetryMessage.powerMetrics) {
				Logger.data.debug("📈 [Telemetry] Power Metrics Received for Node: \(packet.from.toHex(), privacy: .public)")
				telemetry.powerCh1Voltage = telemetryMessage.powerMetrics.hasCh1Voltage.then(telemetryMessage.powerMetrics.ch1Voltage)
				telemetry.powerCh1Current = telemetryMessage.powerMetrics.hasCh1Current.then(telemetryMessage.powerMetrics.ch1Current)
				telemetry.powerCh2Voltage = telemetryMessage.powerMetrics.hasCh2Voltage.then(telemetryMessage.powerMetrics.ch2Voltage)
				telemetry.powerCh2Current = telemetryMessage.powerMetrics.hasCh2Current.then(telemetryMessage.powerMetrics.ch2Current)
				telemetry.powerCh3Voltage = telemetryMessage.powerMetrics.hasCh3Voltage.then(telemetryMessage.powerMetrics.ch3Voltage)
				telemetry.powerCh3Current = telemetryMessage.powerMetrics.hasCh3Current.then(telemetryMessage.powerMetrics.ch3Current)
				telemetry.metricsType = 2
			}
			telemetry.snr = packet.rxSnr
			telemetry.rssi = packet.rxRssi
			// Prefer the sensor's self-reported time, then our receive time, then now — so a remote
			// node reporting time == 0 (no RTC/GPS) never stores as 1970 and gets hidden by the node
			// detail's "latest" sort and the 7-day chart window.
			telemetry.time = resolveTimestamp(telemetryMessage.time, packet.rxTime)
			// Assign via relationship without loading all telemetries
			telemetry.nodeTelemetry = node

			// Keep telemetry bounded as a soft cap during bursts; counting
			// and sorting every telemetry packet does not scale on large meshes.
			let metricsType = telemetry.metricsType
			let nodeNum = packetFrom
			if shouldPruneTelemetryHistory(nodeNum: nodeNum, metricsType: metricsType) {
				let countDescriptor = FetchDescriptor<TelemetryEntity>(
					predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
				)
				let currentCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0
				if currentCount > MeshPackets.maxTelemetryPerType {
					let excess = currentCount - MeshPackets.maxTelemetryPerType
					var pruneDescriptor = FetchDescriptor<TelemetryEntity>(
						predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
						sortBy: [SortDescriptor(\TelemetryEntity.time, order: .forward)]
					)
					pruneDescriptor.fetchLimit = excess
					let toDelete = (try? modelContext.fetch(pruneDescriptor)) ?? []
					for old in toDelete {
						modelContext.delete(old)
					}
				}
			}

			// lastHeard for remote nodes is set centrally in updateAnyPacketFrom, which guards out our
			// own connected node — refresh that one here. It also only updates nodes that already
			// existed when it ran, so a node we just minted from this telemetry packet would have a
			// nil lastHeard (reads as never-heard until the next packet); backfill that case too.
			if connectedNode == Int64(packet.from) || node.lastHeard == nil {
				node.lastHeard = resolveTimestamp(packet.rxTime)
			}
			scheduleDebouncedSave()
			Logger.data.debug("📈 [TelemetryEntity] of type \(MetricsTypes(rawValue: Int(telemetry.metricsType))?.name ?? "Unknown Metrics Type", privacy: .public) buffered for Node: \(packet.from.toHex(), privacy: .public)")
			if telemetry.metricsType == 0 {
				// Connected Device Metrics
				// ------------------------
				// Low Battery notification
				if connectedNode == Int64(packet.from) {
					let batteryLevel = telemetry.batteryLevel ?? 0
					if UserDefaults.lowBatteryNotifications && batteryLevel > 0 && batteryLevel < 4 {
						// Only when the notification will actually fire: snapshot plain values from the
						// SwiftData-backed telemetry/relationships before the MainActor hop, so the
						// deferred Task can't read these context-bound models after they've been
						// invalidated (the same pattern the text-message path follows). Gating first also
						// avoids faulting the user relationship and running the formatter on every packet.
						let notificationID = "notification.lowbattery.\(packet.from)"
						let shortName = telemetry.nodeTelemetry?.user?.shortName ?? "UNK"
						let batteryText = telemetry.batteryLevel?.formatted(.number) ?? Constants.nilValueIndicator
						let nodeNum = telemetry.nodeTelemetry?.num ?? 0
						Task {@MainActor in
							let manager = LocalNotificationManager()
							manager.notifications = [
								Notification(
									id: notificationID,
									title: "Critically Low Battery!",
									subtitle: "AKA \(shortName)",
									content: "Time to charge your radio, there is \(batteryText)% battery remaining.",
									target: "nodes",
									path: "meshtastic:///nodes?nodenum=\(nodeNum)"
								)
							]
							manager.schedule()
						}
					}
				}
			} else if telemetry.metricsType == 4 {
				// Update our live activity if there is one running, not available on mac
#if !targetEnvironment(macCatalyst)
#if canImport(ActivityKit)

				let fifteenMinutesLater = Calendar.current.date(byAdding: .minute, value: (Int(15) ), to: Date())!
				let date = Date.now...fifteenMinutesLater
				let updatedMeshStatus = MeshActivityAttributes.MeshActivityStatus(uptimeSeconds: telemetry.uptimeSeconds.map { UInt32(bitPattern: $0) },
																				  channelUtilization: telemetry.channelUtilization,
																				  airtime: telemetry.airUtilTx,
																				  sentPackets: UInt32(bitPattern: telemetry.numPacketsTx),
																				  receivedPackets: UInt32(bitPattern: telemetry.numPacketsRx),
																				  badReceivedPackets: UInt32(bitPattern: telemetry.numPacketsRxBad),
																				  dupeReceivedPackets: UInt32(bitPattern: telemetry.numRxDupe),
																				  packetsSentRelay: UInt32(bitPattern: telemetry.numTxRelay),
																				  packetsCanceledRelay: UInt32(bitPattern: telemetry.numTxRelayCanceled),
																				  nodesOnline: UInt32(bitPattern: telemetry.numOnlineNodes),
																				  totalNodes: UInt32(bitPattern: telemetry.numTotalNodes),
																				  timerRange: date)

				let alertConfiguration = AlertConfiguration(title: "Mesh activity update", body: "Updated Node Stats Data.", sound: .default)
				let updatedContent = ActivityContent(state: updatedMeshStatus, staleDate: nil)

				let meshActivity = Activity<MeshActivityAttributes>.activities.first(where: { $0.attributes.nodeNum == connectedNode })
				if meshActivity != nil {
					Task {
						// await meshActivity?.update(updatedContent, alertConfiguration: alertConfiguration)
						await meshActivity?.update(updatedContent)
						Logger.services.debug("Updated live activity.")
					}
				}
#endif
#endif
			}
		} else {
			Logger.data.error("💥 Error Decoding Telemetry payload for Node \(packet.from.toHex(), privacy: .public)")
		}
	}

	func textMessageAppPacket(
		packet: MeshPacket,
		wantRangeTestPackets: Bool,
		critical: Bool = false,
		connectedNode: Int64,
		storeForward: Bool = false,
		appState: AppState?
	) async {
		var messageText = String(bytes: packet.decoded.payload, encoding: .utf8)
			let rangeRef = Reference(Int.self)
			let rangeTestRegex = Regex {
				"seq "
				TryCapture(as: rangeRef) {
					OneOrMore(.digit)
				} transform: { match in
					Int(match)
				}
			}
			let rangeTest = messageText?.contains(rangeTestRegex) ?? false && messageText?.starts(with: "seq ") ?? false

			if !wantRangeTestPackets && rangeTest {
				return
			}
			var storeForwardBroadcast = false
			if storeForward {
				if let storeAndForwardMessage = try? StoreAndForward(serializedBytes: packet.decoded.payload) {
					messageText = String(bytes: storeAndForwardMessage.text, encoding: .utf8)
					if storeAndForwardMessage.rr == .routerTextBroadcast {
						storeForwardBroadcast = true
					}
				}
			}

			if messageText?.count ?? 0 > 0 {
				// Detection-sensor and alert events ride the text-message port; label them
				// distinctly in the stream.
				let messageLabel: String
				switch packet.decoded.portnum {
				case .detectionSensorApp: messageLabel = "🔔 [Detection Sensor]"
				case .alertApp:           messageLabel = "🔔 [Alert]"
				default:                  messageLabel = "💬 [Text Message]"
				}
				// A store-and-forward router broadcast is addressed to the local node yet is a channel
				// broadcast everywhere else (toUser == nil, shield shown), so classify it as a broadcast
				// here too rather than treating it as a DM.
				let isBroadcastMessage = packet.to == Constants.maximumNodeNum || storeForwardBroadcast
				// Show channel/broadcast text in the stream; redact direct-message content (only
				// mark it "(DM)") so private 1:1 text isn't persisted to the unified log.
				let messageDetail: String
				if isBroadcastMessage {
					let preview = (messageText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
					messageDetail = preview.count > 100 ? String(preview.prefix(100)) + "…" : preview
				} else {
					messageDetail = "(DM)"
				}
				Logger.mesh.info("\(messageLabel, privacy: .public) packet received from \(packet.from.toHex(), privacy: .public) — \(messageDetail, privacy: .public)")
				let toNum = Int64(packet.to)
				let fromNum = Int64(packet.from)
				let fetchDescriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == toNum || $0.num == fromNum })
				do {
					let fetchedUsers = try modelContext.fetch(fetchDescriptor)
					let newMessage = MessageEntity()
					modelContext.insert(newMessage)
					newMessage.messageId = Int64(packet.id)
					if packet.rxTime > 0 {
						newMessage.messageTimestamp = Int32(bitPattern: packet.rxTime)
					} else {
						newMessage.messageTimestamp = Int32(Date().timeIntervalSince1970)
					}
					if packet.relayNode != 0 {
						newMessage.relayNode = Int64(packet.relayNode)
					}
					newMessage.receivedACK = false
					newMessage.snr = packet.rxSnr
					newMessage.rssi = packet.rxRssi
					newMessage.isEmoji = packet.decoded.emoji == 1
					newMessage.channel = Int32(packet.channel)
					newMessage.portNum = Int32(packet.decoded.portnum.rawValue)
					/// Radio-verified XEdDSA signature for this received broadcast. Firmware only sets this on
					/// broadcasts, but gate on the broadcast classification too so the "verified" shield can
					/// never appear on a DM even if a stray/spoofed packet carries the flag. `isBroadcastMessage`
					/// (computed above) also covers store-and-forward router broadcasts, which are addressed
					/// to the local node yet treated as channel broadcasts (toUser == nil).
					newMessage.xeddsaSigned = packet.xeddsaSigned && isBroadcastMessage
					if packet.decoded.portnum == PortNum.detectionSensorApp {
						if !UserDefaults.enableDetectionNotifications {
							newMessage.read = true
						}
					}
					if packet.decoded.replyID > 0 {
						newMessage.replyID = Int64(packet.decoded.replyID)
					}
					// Updated logic for handling toUser
					if fetchedUsers.first(where: { $0.num == packet.to }) != nil && packet.to != Constants.maximumNodeNum {
						if !storeForwardBroadcast {
							newMessage.toUser = fetchedUsers.first(where: { $0.num == packet.to })
						} else if storeForwardBroadcast {
							// For S&F broadcast messages, treat as a channel message (not a DM)
							newMessage.toUser = nil
						} else {
							do {
								let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.to), context: modelContext)
								newMessage.toUser = newUser
							} catch PersistenceError.invalidInput(let message) {
								Logger.data.error("Error Creating a new UserEntity (Invalid Input) from node number: \(packet.to, privacy: .public) Error:  \(message, privacy: .public)")
							} catch {
								Logger.data.error("Error Creating a new UserEntity from node number: \(packet.to, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
							}
						}
					}
					if fetchedUsers.first(where: { $0.num == packet.from }) != nil {
						newMessage.fromUser = fetchedUsers.first(where: { $0.num == packet.from })
						/// Set the public key for the message
						if newMessage.fromUser?.pkiEncrypted ?? false && packet.pkiEncrypted {
							newMessage.pkiEncrypted = true
							newMessage.publicKey = packet.publicKey
						}

						/// Check for key mismatch
						if let nodeKey = newMessage.fromUser?.publicKey {
							if newMessage.toUser != nil && packet.pkiEncrypted && !packet.publicKey.isEmpty {
								if nodeKey != newMessage.publicKey {
									newMessage.fromUser?.keyMatch = false
									newMessage.fromUser?.newPublicKey = newMessage.publicKey
									let nodeKey = String(nodeKey.base64EncodedString()).prefix(8)
									let messageKey = String(newMessage.publicKey?.base64EncodedString() ?? "No Key").prefix(8)
									Logger.data.error("🔑 Key mismatch original key: \(nodeKey, privacy: .public) . . . new key: \(messageKey, privacy: .public) . . .")
								}
							}
						} else if packet.pkiEncrypted {
							/// We have no key, set it if it is not empty
							if !packet.publicKey.isEmpty {
								newMessage.fromUser?.pkiEncrypted = true
								newMessage.fromUser?.publicKey = packet.publicKey
							}
						}
					} else {
						/// Make a new from user if they are unknown
						do {
							let newUser = try createUser(num: Int64(truncatingIfNeeded: packet.from), context: modelContext)
							// Reuse an existing NodeInfoEntity if present to avoid creating duplicates
							let existingNodeFetchDescriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == fromNum })
							let existingNodes = try modelContext.fetch(existingNodeFetchDescriptor)
							if let existingNode = existingNodes.first {
								existingNode.user = newUser
							} else {
								let newNode = NodeInfoEntity()
								modelContext.insert(newNode)
								newNode.id = Int64(newUser.num)
								newNode.num = Int64(newUser.num)
								newNode.user = newUser
							}
							newMessage.fromUser = newUser
						} catch PersistenceError.invalidInput(let message) {
							Logger.data.error("Error Creating a new UserEntity (Invalid Input) from node number: \(packet.from, privacy: .public) Error:  \(message, privacy: .public)")
						} catch {
							Logger.data.error("Error Creating a new UserEntity from node number: \(packet.from, privacy: .public) Error:  \(error.localizedDescription, privacy: .public)")
						}
					}
					// Keep this write: a first-time sender's node is created here, a path
					// updateAnyPacketFrom (existing remote nodes only) doesn't cover.
					if packet.rxTime > 0 {
						newMessage.fromUser?.userNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
					} else {
						newMessage.fromUser?.userNode?.lastHeard = Date()
					}
					newMessage.messagePayload = messageText
					newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: messageText!)
					if packet.to != Constants.maximumNodeNum && newMessage.fromUser != nil {
						newMessage.fromUser?.lastMessage = Date()
					}
					var messageSaved = false
					do {
						if modelContext.hasChanges {
							try modelContext.save()
						}
						Logger.data.debug("💾 Saved a new message for \(newMessage.messageId, privacy: .public)")
						messageSaved = true

						// Keep message storage bounded without scanning the whole table
						// after every incoming text.
						if shouldPruneMessageHistory() {
							let countDescriptor = FetchDescriptor<MessageEntity>()
							let totalMessages = (try? modelContext.fetchCount(countDescriptor)) ?? 0
							if totalMessages > MeshPackets.maxTotalMessages {
								var oldestDescriptor = FetchDescriptor<MessageEntity>(
									sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .forward)]
								)
								oldestDescriptor.fetchLimit = totalMessages - MeshPackets.maxTotalMessages
								if let oldMessages = try? modelContext.fetch(oldestDescriptor) {
									for old in oldMessages {
										modelContext.delete(old)
									}
									try modelContext.save()
									Logger.data.info("🗑️ Pruned \(oldMessages.count) old messages (cap: \(MeshPackets.maxTotalMessages))")
								}
							}
						}
					} catch {
						Logger.data.error("💥 Failed to save new MessageEntity: \(error.localizedDescription, privacy: .public)")
					}
					// Send notifications if the message saved properly to core data
					if messageSaved {
						// Donate to SiriKit so the message appears in CarPlay Messages
						#if os(iOS)
						CarPlayIntentDonation.donateReceivedMessage(newMessage)
						#endif

						if packet.decoded.portnum == PortNum.detectionSensorApp && !UserDefaults.enableDetectionNotifications {
							return
						}
						if newMessage.fromUser != nil && newMessage.toUser != nil {
							// Set Unread Message Indicators
							if packet.to == connectedNode {
								let unreadCount = await newMessage.toUser?.unreadMessages(context: modelContext, skipLastMessageCheck: true) ?? 0 // skipLastMessageCheck=true because we don't update lastMessage on our own connected node
								Task { @MainActor in
									appState?.unreadDirectMessages = unreadCount
								}
							}
							if !(newMessage.fromUser?.mute ?? false) && newMessage.isEmoji == false {
								// Build the notification from the model objects now, while this context is valid,
								// and capture only the resulting value — a deferred Task must not hold `newMessage`
								// (a context-bound model), since a device switch can reset this context first
								// ("destroyed by ModelContext.reset").
								let senderName = newMessage.fromUser?.longName ?? "Unknown".localized
								var dmNotification = Notification(
									id: ("notification.id.\(newMessage.messageId)"),
									title: "\(senderName)",
									subtitle: "AKA \(newMessage.fromUser?.shortName ?? "?")",
									content: messageText!,
									target: "messages",
									path: "meshtastic:///messages?userNum=\(newMessage.fromUser?.num ?? 0)&messageId=\(newMessage.isEmoji ? newMessage.replyID : newMessage.messageId)",
									messageId: newMessage.messageId,
									channel: newMessage.channel,
									userNum: Int64(packet.from),
									critical: critical
								)
								#if os(iOS)
								dmNotification.senderIntent = CarPlayIntentDonation.incomingMessageIntent(from: newMessage)
								#endif
								let notification = dmNotification
								Task {@MainActor in
									let manager = LocalNotificationManager()
									manager.notifications = [notification]
									manager.schedule()
									Logger.services.debug("iOS Notification Scheduled for text message from \(senderName, privacy: .public)")
								}
							}
						} else if newMessage.fromUser != nil && newMessage.toUser == nil {
							let myInfoFetchDescriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == connectedNode })
							do {
								let fetchedMyInfo = try modelContext.fetch(myInfoFetchDescriptor)
								if let myInfo = fetchedMyInfo.first {
									// Snapshot everything off this context NOW, synchronously, and capture only
									// plain values into the deferred Task. The entity (and `newMessage`) must not
									// cross the hop: a device switch can reset this context before the Task runs,
									// which traps with "destroyed by ModelContext.reset" on access.
									//
									// unreadMessages is O(unread); recomputing it for the badge on every incoming
									// channel message is quadratic over a burst and stalls slower devices. Throttle
									// to ~1/sec — the badge tolerates brief lag and resyncs on app-active and on read.
									let recountUnread = shouldRecomputeChannelUnread()
									let connectedNodeNum = connectedNode
									let shouldNotify = UserDefaults.channelMessageNotifications && newMessage.isEmoji == false && myInfo.channels.contains(where: { $0.index == newMessage.channel && !$0.mute })
									var channelNotification: Notification?
									if shouldNotify {
										var chNotification = Notification(
											id: ("notification.id.\(newMessage.messageId)"),
											title: "\(newMessage.fromUser?.longName ?? "Unknown".localized)",
											subtitle: "AKA \(newMessage.fromUser?.shortName ?? "?")",
											content: messageText!,
											target: "messages",
											path: "meshtastic:///messages?channelId=\(newMessage.channel)&messageId=\(newMessage.isEmoji ? newMessage.replyID : newMessage.messageId)",
											messageId: newMessage.messageId,
											channel: newMessage.channel,
											userNum: Int64(newMessage.fromUser?.userId ?? "0"),
											critical: critical
										)
										#if os(iOS)
										chNotification.senderIntent = CarPlayIntentDonation.incomingMessageIntent(from: newMessage)
										#endif
										channelNotification = chNotification
									}
									let notification = channelNotification
									Task {@MainActor in
										if recountUnread {
											// Recompute the badge against a freshly re-fetched, live main-context
											// entity (unreadMessages is @MainActor); never touch the captured
											// MeshPackets entity, which a device switch may have invalidated.
											let mainContext = PersistenceController.shared.context
											let liveDescriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == connectedNodeNum })
											if let liveMyInfo = try? mainContext.fetch(liveDescriptor).first {
												appState?.unreadChannelMessages = liveMyInfo.unreadMessages(context: mainContext)
											}
										}
										if let notification {
											let manager = LocalNotificationManager()
											manager.notifications = [notification]
											manager.schedule()
											Logger.services.debug("iOS Notification Scheduled for channel text message")
										}
									}
								}
							} catch {
								// Handle error
							}
						}
					}
			} catch {
				Logger.data.error("Fetch Message To and From Users Error")
			}
		}
	}

	func waypointPacket (packet: MeshPacket) {
		let waypointDetail = (try? Waypoint(serializedBytes: packet.decoded.payload)).map { w -> String in
			var parts: [String] = []
			let name = w.name.trimmingCharacters(in: .whitespacesAndNewlines)
			if !name.isEmpty { parts.append(name) }
			if w.latitudeI != 0 || w.longitudeI != 0 {
				parts.append(String(format: "%.5f,%.5f", Double(w.latitudeI) / 1e7, Double(w.longitudeI) / 1e7))
			}
			return parts.isEmpty ? "" : " — " + parts.joined(separator: " ")
		} ?? ""
		Logger.mesh.info("[Waypoint] packet received from \(packet.from.toHex(), privacy: .public)\(waypointDetail, privacy: .public)")

		do {
			if let waypointMessage = try? Waypoint(serializedBytes: packet.decoded.payload) {
				// Fetch waypoint by waypointMessage.id, not packet.id
				let waypointId = Int64(waypointMessage.id)
				let fetchWaypointDescriptor = FetchDescriptor<WaypointEntity>(predicate: #Predicate { $0.id == waypointId })

				let fetchedWaypoint = try modelContext.fetch(fetchWaypointDescriptor)
				// Fetch the node info to get the short name
				var nodeShortName: String = "?"
				let packetFrom = Int64(packet.from)
				let fetchNodeDescriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == packetFrom })
				do {
					let fetchedNode = try modelContext.fetch(fetchNodeDescriptor)
					if let node = fetchedNode.first, let user = node.user {
						nodeShortName = user.shortName ?? node.user?.userId ?? String(packet.from.toHex())
					}
				} catch {
					Logger.data.error("Failed to fetch NodeInfoEntity for node \(packet.from.toHex(), privacy: .public): \(error)")
				}
				if fetchedWaypoint.isEmpty {
					// Create a new waypoint
					let waypoint = WaypointEntity()
					modelContext.insert(waypoint)
					waypoint.id = Int64(waypointMessage.id) // Use waypointMessage.id
					waypoint.name = waypointMessage.name
					waypoint.longDescription = waypointMessage.description_p
					waypoint.latitudeI = waypointMessage.latitudeI
					waypoint.longitudeI = waypointMessage.longitudeI
					waypoint.icon = Int64(waypointMessage.icon)
					waypoint.locked = waypointMessage.lockedTo != 0
					waypoint.createdBy = Int64(packet.from)
					if waypointMessage.expire >= 1 {
						waypoint.expire = Date(timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire)))
					} else {
						waypoint.expire = nil
					}
					waypoint.created = Date()
					savePendingChanges()
					Logger.data.info("💾 Added Node Waypoint App Packet For: \(waypoint.id, privacy: .public)")

					Task { @MainActor in
							let manager = LocalNotificationManager()
							let icon = String(UnicodeScalar(Int(waypoint.icon)) ?? "📍")
							let latitude = Double(waypoint.latitudeI) / 1e7
							let longitude = Double(waypoint.longitudeI) / 1e7
							manager.notifications = [
								Notification(
									id: ("notification.id.\(waypoint.id)"),
									title: "New Waypoint From \(nodeShortName)",
									subtitle: "\(icon) \(waypoint.name ?? "Dropped Pin")",
									content: "\(waypoint.longDescription ?? "\(latitude), \(longitude)")",
									target: "map",
									path: "meshtastic:///map?waypointid=\(waypoint.id)"
								)
							]
							Logger.data.debug("meshtastic:///map?waypointid=\(waypoint.id, privacy: .public)")
							manager.schedule()
						}
				} else {
					// Update existing waypoint
					let existingWaypoint = fetchedWaypoint[0]
					if !existingWaypoint.locked {
						let currentTime = Int64(Date().timeIntervalSince1970)
						if waypointMessage.expire > 0 && waypointMessage.expire <= currentTime {
							modelContext.delete(existingWaypoint)
							savePendingChanges()
							Logger.data.info("💾 Deleted a waypoint")
						} else {
							existingWaypoint.name = waypointMessage.name
							existingWaypoint.longDescription = waypointMessage.description_p
							existingWaypoint.latitudeI = waypointMessage.latitudeI
							existingWaypoint.longitudeI = waypointMessage.longitudeI
							existingWaypoint.icon = Int64(waypointMessage.icon)
							existingWaypoint.locked = waypointMessage.lockedTo != 0
							existingWaypoint.lastUpdatedBy = Int64(packet.from)
							if waypointMessage.expire >= 1 {
								existingWaypoint.expire = Date(timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire)))
							} else {
								existingWaypoint.expire = nil
							}
							existingWaypoint.lastUpdated = Date()
							savePendingChanges()
							Logger.data.info("💾 Updated Node Waypoint App Packet For: \(existingWaypoint.id, privacy: .public)")
						}
					}
				}
			}
		} catch {
			Logger.mesh.error("Error Deserializing WAYPOINT_APP packet.")
		}
	}
}

extension Position {
	/// True when the position carries usable, non-placeholder coordinates.
	///
	/// Requires both components to be non-zero, matching the app-wide coordinate convention
	/// (see `PositionEntity.nodeCoordinate`): a position with one axis unset/zero is treated
	/// as "no location" and would not render, so it must not be persisted as a valid fix.
	/// The Apple Park simulator default is also rejected — but only the exact placeholder,
	/// since a real position that shares just one coordinate with Apple Park is legitimate.
	var hasValidCoordinates: Bool {
		guard latitudeI != 0, longitudeI != 0 else { return false }
		let isApplePark = latitudeI == 373346000 && longitudeI == -1220090000
		return !isApplePark
	}
}

extension NodeInfo {
	var isValidPosition: Bool {
		hasPosition && position.hasValidCoordinates
	}
}
