//
//  AccessoryManager+FromRadio.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/18/25.
//

import CryptoKit
import Foundation
import MeshtasticProtobufs
import CocoaMQTT
import OSLog
@preconcurrency import SwiftData

extension AccessoryManager {

	/// `session`: the radio it came from. With other radios connected, the notice names it.
	func handleClientNotification(_ clientNotification: ClientNotification, session: RadioSession? = nil) {
		Logger.services.info("handleClientNotification: \(clientNotification.debugDescription)")
		var path = "meshtastic:///settings/debugLogs"
		if clientNotification.hasReplyID {
			/// Set Sent bool on TraceRouteEntity to false if we got rate limited
			if clientNotification.message.starts(with: "TraceRoute") {
				// CoreData operation happens on the Main Actor

				let traceRoute = getTraceRoute(id: Int64(clientNotification.replyID), context: context)
				traceRoute?.sent = false
				do {
					try context.save()
					Logger.data.info("💾 [TraceRouteEntity] Trace Route Rate Limited")
				} catch {
					let nsError = error as NSError
					Logger.data.error("💥 [TraceRouteEntity] Error Updating Core Data: \(nsError, privacy: .public)")
				}

			}

			switch clientNotification.payloadVariant {
			case .lowEntropyKey, .duplicatedPublicKey:
				path = "meshtastic:///settings/security"
			default:
				break
			}
		}

		// Always log, whether or not the user is alerted — Debug Logs stays complete.
		Logger.services.error("⚠️ Client Notification: \(clientNotification.message, privacy: .private)")

		// The radio answers an OTA request with one of these, and it is the only place it says
		// why it would not start. Log it in the clear — it names a hardware capability, not
		// anything about the user — and hand it to the update sheet, which otherwise sits there
		// until it times out waiting for a device that never rebooted.
		if clientNotification.message.contains("OTA") {
			Logger.services.error("📡 [ESP32 OTA] Radio says: \(clientNotification.message, privacy: .public)")
			NotificationCenter.default.post(name: .otaDeviceNotice, object: clientNotification.message)
		}

		let key = Self.noticeKey(for: clientNotification)
		guard shouldSurfaceFirmwareNotice(key: key, isSecurity: Self.isSecurityNotice(clientNotification)) else {
			Logger.services.debug("⏳ Firmware notification suppressed by backoff: \(key, privacy: .private)")
			return
		}

		// TODO: Look at this to see if LocationManager should be singleton
		let manager = LocalNotificationManager()
		manager.notifications = [
			Notification(
				// Per-message id: a fixed one let an unrelated notice silently replace a
				// security warning that was still pending.
				id: "client.notification.\(Self.noticeIdentifierFragment(key))",
				title: "Firmware Notification".localized,
				subtitle: firmwareNoticeSubtitle(level: clientNotification.level, session: session),
				content: clientNotification.message,
				target: "settings",
				path: path
			)
		]
		manager.schedule()
	}

	/// The level, and the radio's name when more than one radio is connected (T071).
	func firmwareNoticeSubtitle(level: LogRecord.Level, session: RadioSession?) -> String {
		let levelText = "\(level)".capitalized
		guard connectedRadioCount > 1, let device = session?.device else { return levelText }
		return levelText + " · " + String.localizedStringWithFormat("on %@".localized, device.shortName ?? device.longName ?? device.name)
	}

	// MARK: - Firmware notification backoff

	/// Whether this notice should alert the user now.
	///
	/// Firmware repeats some notices on a timer — "Location sharing is disabled on this
	/// channel" fires on every position interval when a channel deliberately has position
	/// off, which on event firmware is configuration rather than a fault. A flat
	/// suppression window can't serve both cases: short enough to report a real fault
	/// promptly is short enough to nag. So repeats back off instead — immediate, then 5
	/// minutes, 30, 2 hours, then once every 12. A one-off still alerts with no delay; a
	/// standing condition settles to once or twice a day on its own.
	///
	/// Security notices never back off: they are rare, actionable, and the failure mode
	/// worth avoiding is burying them.
	func shouldSurfaceFirmwareNotice(key: String, isSecurity: Bool, now: Date = .now) -> Bool {
		guard !isSecurity else { return true }

		// Forget anything quiet for longer than the cap, so the map can't grow unbounded
		// and a recurrence after a real lull is treated as new.
		firmwareNoticeHistory = firmwareNoticeHistory.filter {
			now.timeIntervalSince($0.value.lastShown) <= Self.firmwareNoticeForgetAfter
		}

		guard let entry = firmwareNoticeHistory[key] else {
			firmwareNoticeHistory[key] = (count: 1, lastShown: now)
			return true
		}
		let step = min(entry.count, Self.firmwareNoticeBackoff.count - 1)
		guard now.timeIntervalSince(entry.lastShown) >= Self.firmwareNoticeBackoff[step] else {
			return false
		}
		firmwareNoticeHistory[key] = (count: entry.count + 1, lastShown: now)
		return true
	}

	/// Identity of a notice. The structured payload variant when there is one, so a
	/// reworded firmware string stays the same notice; otherwise level plus message.
	static func noticeKey(for notification: ClientNotification) -> String {
		switch notification.payloadVariant {
		case .lowEntropyKey: return "lowEntropyKey"
		case .duplicatedPublicKey: return "duplicatedPublicKey"
		case .keyVerificationNumberInform: return "keyVerificationNumberInform"
		case .keyVerificationNumberRequest: return "keyVerificationNumberRequest"
		case .keyVerificationFinal: return "keyVerificationFinal"
		case .none: return "\(notification.level)|\(notification.message)"
		}
	}

	/// Security notices bypass the backoff entirely.
	static func isSecurityNotice(_ notification: ClientNotification) -> Bool {
		switch notification.payloadVariant {
		case .lowEntropyKey, .duplicatedPublicKey, .keyVerificationNumberInform,
			 .keyVerificationNumberRequest, .keyVerificationFinal:
			return true
		case .none:
			return false
		}
	}

	/// A notification identifier fragment: readable in logs, stable across launches, and
	/// bounded in length.
	/// A readable prefix plus a digest of the complete key. Normalization alone
	/// collides ("a-b" and "a_b" both become "a_b"), and so do long keys sharing a
	/// truncated prefix — colliding identifiers make one pending notification
	/// silently replace another.
	static func noticeIdentifierFragment(_ key: String) -> String {
		let digest = SHA256.hash(data: Data(key.utf8))
			.prefix(4)
			.map { String(format: "%02x", $0) }
			.joined()
		let allowed = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
		return String(String(allowed).prefix(55)) + "_" + digest
	}

	/// `session` is the connection the MyInfo arrived on; nil means the active one.
	func handleMyInfo(_ myNodeInfo: MyNodeInfo, session: RadioSession? = nil) async {
		// TODO: this works for connections like BLE that have a uniqueId, but what about ones like serial?
		guard let session = session ?? activeConnection else {
			Logger.services.error("⚠️ Failed to decode MyInfo, no connected device ID")
			return
		}
		let connectedDeviceId = session.device.id.uuidString
		Logger.services.info("handleMyInfo: \(myNodeInfo.debugDescription)")
		let isFirst = session === activeConnection
		// The same radio connected twice (over BLE and TCP, say): the second link goes, and isn't
		// retried, without touching the radio's remembered state, which is the first link's (T154).
		let reportedNum = Int64(myNodeInfo.myNodeNum)
		let otherSessions = [activeConnection].compactMap { $0 } + Array(additionalRadios.values)
		if !isFirst, otherSessions.contains(where: { $0 !== session && $0.device.num == reportedNum }) {
			Logger.transport.error("🔗➕ [Additional] \(session.device.name, privacy: .public) reports the node number of a radio that's already connected; disconnecting it")
			additionalRadioReconnects.removeValue(forKey: session.device.id)?.cancel()
			await disconnectAdditionalRadio(session.device.id)
			return
		}

		updateDevice(deviceId: session.device.id, key: \.num, value: Int64(myNodeInfo.myNodeNum))

		// Feature 021 (shared store, T066): a radio the store hasn't seen before simply joins it;
		// every row is scoped to the radio it came through (observations, receptions,
		// `localNodeNum`). The one case still handled here is the same radio reporting a new
		// node number (2.8 upgrade), which renumbers the store instead of adding a stranger.
		// This used to back up and wipe the store for any unfamiliar radio, which would now
		// erase the other connected radios' data.
		await renumberIfSameRadio(
			incomingNodeNum: Int64(myNodeInfo.myNodeNum),
			incomingDeviceId: myNodeInfo.deviceID,
			peripheralId: connectedDeviceId
		)

		let myInfoId = await MeshPackets.shared.myInfoPacket(myInfo: myNodeInfo, peripheralId: connectedDeviceId)

		// Move this radio's backup onto its device id if it is still filed under a node number, and
		// collapse anything left behind by earlier renumbers. Cheap after the first connect.
		await NodeBackupManager.shared.adoptLegacyBackups(
			deviceId: myNodeInfo.deviceID,
			nodeNum: Int64(myNodeInfo.myNodeNum),
			peripheralId: connectedDeviceId
		)

		// Resolve on a throwaway context, NOT the long-lived main context. After a database clear
		// (manual reset, or the clear inside a device switch) the main context can still hold an
		// invalidated instance registered under a rowid that SwiftData then reuses for the
		// freshly-inserted row — model(for:) would hand that dead instance back and accessing it
		// traps with "destroyed by ModelContext.reset". A fresh context has no such registrations,
		// so it faults the current row from the store.
		let myInfoResolveContext = ModelContext(context.container)
		if let myInfoId, let myInfo = try? myInfoResolveContext.model(for: myInfoId) as? MyInfoEntity {
			if let bleName = myInfo.bleName {
				updateDevice(deviceId: session.device.id, key: \.name, value: bleName)
				updateDevice(deviceId: session.device.id, key: \.longName, value: bleName)
			}

			if myNodeInfo.nodedbCount > 0 {
				update(session, \.expectedNodeDBSize, to: Int(myNodeInfo.nodedbCount))
			}

			// The preferred radio is the first one.
			if isFirst {
				// Compare BEFORE persisting the new num — the previous code assigned first, so
				// newConnection was always false and this hook was dead.
				let newConnection = PreferredRadio.nodeNum != Int64(myInfo.myNodeNum)
				PreferredRadio.nodeNum = Int64(myInfo.myNodeNum)
				if newConnection {
					// Onboard a new device connection here
				}
			}
		}
		await beginAutomaticChannelRefreshStageIfNeeded(for: Int64(myNodeInfo.myNodeNum), session: session)

		update(session, \.firmwareEdition, to: FirmwareEditions(from: myNodeInfo.firmwareEdition))
		if session.device.longName == nil {
			updateDevice(deviceId: session.device.id, key: \.longName, value: session.device.name)
		}
		guard isFirst else { return }

		// Auto-disable new-node notifications for event firmware editions
		applyEventFirmwareNotificationDefaults(myNodeInfo.firmwareEdition)

		// Initialize TAK bridge for TAK integration
		initializeTAKBridge()
	}

	/// Renumbers the store when the connecting radio is one it already knows under another
	/// node number (a 2.8 firmware upgrade changes the number a radio reports). Any other radio
	/// joins the shared store as it is (feature 021): no backup, no reset.
	private func renumberIfSameRadio(incomingNodeNum: Int64, incomingDeviceId: Data, peripheralId: String) async {
		// Fresh throwaway context: no stale registrations, and this runs before any ingest for
		// the connecting radio, so what it sees is exactly what earlier sessions left behind.
		let checkContext = ModelContext(context.container)
		guard let myInfos = try? checkContext.fetch(FetchDescriptor<MyInfoEntity>()), !myInfos.isEmpty else {
			return // Fresh/empty store.
		}
		guard !myInfos.contains(where: { $0.myNodeNum == incomingNodeNum }) else {
			return // A radio the store already knows under this number.
		}

		if let sameRadio = Self.sameRadio(among: myInfos, incomingDeviceId: incomingDeviceId, peripheralId: peripheralId) {
			await renumberStore(from: sameRadio.myNodeNum, to: incomingNodeNum, deviceId: incomingDeviceId)
			return
		}

		let known = myInfos.map { $0.myNodeNum.toHex() }.joined(separator: ", ")
		Logger.data.info("💾 [Database] Node \(incomingNodeNum.toHex(), privacy: .public) joins the shared store (already holds \(known, privacy: .public))")
	}

	/// The radio the store knows that the connecting one is, under an old node number.
	///
	/// device_id is the radio's own hardware identifier, so it holds over TCP and serial where
	/// there is no BLE identifier, and it survives a re-pair. The MyInfo row also records the
	/// peripheral it came from, which is the fallback only when a device id is missing on either
	/// side (T165): serial ids hash the port path and manual TCP ids hash host:port, so a different
	/// radio on the same port or address has the same peripheral id, and with two device ids that
	/// differ it is another radio, whose history mustn't be renamed.
	static func sameRadio(among myInfos: [MyInfoEntity], incomingDeviceId: Data, peripheralId: String) -> MyInfoEntity? {
		if !incomingDeviceId.isEmpty, let match = myInfos.first(where: { $0.deviceId == incomingDeviceId }) {
			return match
		}
		return myInfos.first { myInfo in
			myInfo.peripheralId == peripheralId && (incomingDeviceId.isEmpty || (myInfo.deviceId ?? Data()).isEmpty)
		}
	}

	/// Rewrites the store from the node number this radio used to report to the one it reports
	/// now. Runs before any data for the new number is ingested, so what it rewrites is exactly
	/// what the previous session left behind.
	private func renumberStore(from oldNum: Int64, to newNum: Int64, deviceId: Data) async {
		Logger.data.warning("💾 [Database] Node \(oldNum.toHex(), privacy: .public) now reports \(newNum.toHex(), privacy: .public) — same radio, renumbering the store")

		// The backup is the safety net if the rewrite goes wrong, so flush first — it copies the
		// store files, and anything still waiting on a debounced save would not be in them yet.
		await MeshPackets.shared.flushDebouncedSaves()
		let previousName = devices.first(where: { $0.num == oldNum })?.longName
		// Same physical radio either side of the renumber, so the backup keys on the id it reports now.
		_ = await NodeBackupManager.shared.createBackup(forNode: oldNum, deviceId: deviceId, nodeName: previousName)

		// Detail views bound to the old node have to unmount before its identity changes
		// underneath them, the same reason the reset path pops first. Every open
		// window has its own router; pop them all and leave each window's tab.
		if let appState {
			appState.windows.popAllStacks()
			await Task.yield()
		}

		guard NodeRenumber.apply(from: oldNum, to: newNum, in: context) else {
			// Leave the store alone rather than half-renumbering it. The connect carries on and
			// the radio arrives as a new node, which is what happened before this existed.
			Logger.data.error("💾 [Database] Renumbering failed, leaving the store as it is")
			return
		}
		// With several radios, only the preferred radio's own renumber moves the preference.
		if PreferredRadio.nodeNum == oldNum {
			PreferredRadio.nodeNum = newNum
		}
		// The radio the store's old rows belong to, if it's this one (T213).
		BackfillOwner.renumber(from: oldNum, to: newNum)
		Self.moveSavedRadioChoices(from: oldNum, to: newNum)
		appState?.databaseResetID = UUID()
	}

	/// Choices saved by a radio's node number follow it to its new number (T214): the radios TAK,
	/// CarPlay & Siri and the Watch use, the Heard By filter, and the radio to connect first.
	/// Otherwise they'd name a number no radio has and quietly fall back.
	/// `filters` defaults to every open window's.
	static func moveSavedRadioChoices(from oldNum: Int64, to newNum: Int64, store: UserDefaults = .standard, filters: [NodeFilterParameters]? = nil) {
		for service in RadioService.allCases where UserDefaults.serviceRadio(service, in: store) == oldNum {
			UserDefaults.setServiceRadio(newNum, for: service, in: store)
		}
		NodeFilterParameters.moveHeardByRadio(from: oldNum, to: newNum, store: store, filters: filters)
	}

	/// When event firmware is detected (DEFCON, BURNING_MAN, OPEN_SAUCE, etc.),
	/// auto-disable new-node notifications on first connection when the user has them enabled.
	/// Reconnecting to vanilla firmware restores only a preference that the app changed.
	func applyEventFirmwareNotificationDefaults(_ edition: FirmwareEdition) {
		let current = EventFirmwareNotificationSettings(
			newNodeNotifications: UserDefaults.newNodeNotifications,
			autoDisabledForEvent: UserDefaults.nodeNotificationsAutoDisabledForEvent,
			userOverrideForEvent: UserDefaults.nodeNotificationsUserOverrideForEvent
		)
		let updated = EventFirmwareNotificationPolicy.updatedSettings(for: edition, current: current)
		guard updated != current else { return }

		UserDefaults.newNodeNotifications = updated.newNodeNotifications
		UserDefaults.nodeNotificationsAutoDisabledForEvent = updated.autoDisabledForEvent
		UserDefaults.nodeNotificationsUserOverrideForEvent = updated.userOverrideForEvent
		if edition == .vanilla {
			Logger.services.info("Vanilla firmware detected, re-enabled new node notifications")
		} else {
			Logger.services.info("Event firmware detected (\(String(describing: edition))), auto-disabled new node notifications")
		}
	}

	func handleNodeInfo(_ nodeInfo: NodeInfo, session: RadioSession? = nil) async {
		let session = session ?? activeConnection
		session?.databaseResponseArrived = true
		if let continuation = session?.firstDatabaseNodeInfoContinuation {
			session?.firstDatabaseNodeInfoContinuation = nil
			continuation.resume()
		}

		guard nodeInfo.num > 0 else {
			Logger.services.error("NodeInfo packet with a zero nodeNum")
			return
		}

		// TODO: nodeInfoPacket's channel: parameter is not used
		// Defer the save: during the node-DB dump this handler runs once per node, and a
		// save-per-node on the ingestion actor (plus a main-actor hop each way) was the
		// throughput cliff behind slow/hung connects on large meshes. Deferred writes are
		// flushed by the actor's debounced save (at most every 5s) and finally at
		// configCompleteID (NONCE_ONLY_DB), which also batch-saves the main context.
		_ = await MeshPackets.shared.nodeInfoPacket(nodeInfo: nodeInfo, channel: 0, deferSave: true, connectedNodeNum: session?.nodeNum)

		// Update the connected device's display metadata straight from the protobuf — the
		// previous code resolved the just-inserted entity on a fresh ModelContext for every
		// node in the dump only to read fields the proto already carries.
		if let activeDevice = session?.device, activeDevice.num == Int64(nodeInfo.num), nodeInfo.hasUser {
			let shortName = nodeInfo.user.shortName
			let longName = nodeInfo.user.longName
			let hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
			updateDevice(deviceId: activeDevice.id, key: \.shortName, value: shortName.isEmpty ? "?" : shortName)
			updateDevice(deviceId: activeDevice.id, key: \.longName, value: longName.isEmpty ? "Unknown".localized : longName)
			updateDevice(deviceId: activeDevice.id, key: \.hardwareModel, value: hwModel)
			if session === activeConnection {
				Logger.datadog.setRadioContext(.hardwareModel, hwModel)
			}

			if activeDevice.isManualConnection {
				// We just received a NodeInfo for the currently connected node and this is a
				// manual connection.  Update the metadata for the device entry in UserDefaults
				// with this information for better display later
				ManualConnectionList.shared.updateDevice(deviceId: activeDevice.id, key: \.shortName, value: shortName.isEmpty ? nil : shortName)
				ManualConnectionList.shared.updateDevice(deviceId: activeDevice.id, key: \.longName, value: longName.isEmpty ? nil : longName)
				ManualConnectionList.shared.updateDevice(deviceId: activeDevice.id, key: \.hardwareModel, value: hwModel)
			}
		}

		// Bump the nodeCount: the radio's own, and the first radio's shown progress.
		session?.databaseNodeCount += 1
		if session === activeConnection, case let .retrievingDatabase(nodeCount: nodeCount) = self.state {
			updateState(.retrievingDatabase(nodeCount: nodeCount+1))
		}

	}

	func handleChannel(_ channel: Channel, session: RadioSession? = nil) async {
		guard let deviceNum = (session ?? activeConnection)?.device.num else {
			Logger.data.error("Attempt to process channel information when no connected device.")
			return
		}

		await MeshPackets.shared.channelPacket(channel: channel, fromNum: Int64(truncatingIfNeeded: deviceNum))

	}

	func handleConfig(_ config: Config, session: RadioSession? = nil) async {
		guard let device = (session ?? activeConnection)?.device, let deviceNum = device.num, let longName = device.longName else {
			Logger.data.error("Attempt to process channel information when no connected device.")
			return
		}

		// Local config parses out the variants.  Should we do that here maybe?
		await MeshPackets.shared.localConfig(config: config, nodeNum: Int64(truncatingIfNeeded: deviceNum), nodeLongName: longName)

		// Handle Timezone
		if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
			var dc = config.device
			if dc.tzdef.isEmpty {
				dc.tzdef =  TimeZone.current.posixDescription
				Task {
					try? await saveTimeZone(config: dc, user: deviceNum)
				}
			}
		}
	}

	func handleModuleConfig(_ moduleConfigPacket: ModuleConfig, session: RadioSession? = nil) async {
		guard let device = (session ?? activeConnection)?.device, let deviceNum = device.num, let longName = device.longName else {
			Logger.services.error("Attempt to process channel information when no connected device.")
			return
		}
		await MeshPackets.shared.moduleConfig(config: moduleConfigPacket, nodeNum: Int64(truncatingIfNeeded: deviceNum), nodeLongName: longName)
		// Get Canned Message Message List if the Module is Canned Messages
		if moduleConfigPacket.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(moduleConfigPacket.cannedMessage) {
			try? getCannedMessageModuleMessages(destNum: deviceNum, wantResponse: true)
		}
		// Get the Ringtone if the Module is External Notifications
		if moduleConfigPacket.payloadVariant == ModuleConfig.OneOf_PayloadVariant.externalNotification(moduleConfigPacket.externalNotification) {
			try? getRingtone(destNum: deviceNum, wantResponse: true)
		}
	}

	/// Decode the region → legal-preset map the radio advertises during the
	/// want_config handshake (2.8+). Stored on the AccessoryManager so the LoRa
	/// config screen can constrain its preset picker to the selected region's
	/// legal set. Older firmware never sends this; the map simply stays empty and
	/// the UI falls back to its unconstrained behavior.
	func handleRegionPresets(_ regionPresets: LoRaRegionPresetMap, session: RadioSession) {
		let decoded = regionPresets.decoded()
		update(session, \.loRaRegionPresets, to: decoded)
		Logger.services.info("✅ [handleRegionPresets] decoded \(decoded.count, privacy: .public) region(s) from \(regionPresets.groups.count, privacy: .public) preset group(s)")
	}

	func handleDeviceMetadata(_ metadata: DeviceMetadata, session: RadioSession? = nil) async {
		// Note: moved firmware version check to be inline with connection process
		guard let session = session ?? activeConnection, let deviceNum = session.device.num else {
			Logger.services.error("Attempt to process device metadata information when no connected device.")
			return
		}

		Logger.transport.debug("[Version] handleDeviceMetadata returned version: \(metadata.firmwareVersion)")

		updateDevice(deviceId: session.device.id, key: \.firmwareVersion, value: metadata.firmwareVersion)
		if !metadata.firmwareVersion.isEmpty {
			knownFirmwareVersions[deviceNum] = metadata.firmwareVersion
		}
		if session === activeConnection {
			Logger.datadog.setRadioContext(.firmwareVersion, metadata.firmwareVersion)
		}

		await MeshPackets.shared.deviceMetadataPacket(metadata: metadata, fromNum: deviceNum)
		Logger.transport.info("✅ [handleDeviceMetadata] deviceMetadataPacket completed for \(deviceNum.toHex(), privacy: .public)")
	}

	internal func tryClearExistingChannels() {
		guard let device = activeConnection?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to clear existing channels when no connected device.")
			return
		}

		// Before we get started delete the existing channels from the myNodeInfo
		let num = Int64(deviceNum)
		let fetchMyInfoRequest = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == num })

		do {
			let fetchedMyInfo = try context.fetch(fetchMyInfoRequest)
			if fetchedMyInfo.count == 1 {
				let channelsToDelete = fetchedMyInfo[0].channels
				for channel in channelsToDelete {
					context.delete(channel)
				}
				fetchedMyInfo[0].channels.removeAll()

				// Clean orphaned channels from older app versions where channels were
				// detached but not deleted, which can create duplicate rows in queries.
				let allChannels = try context.fetch(FetchDescriptor<ChannelEntity>())
				for channel in allChannels where channel.myInfoChannel == nil {
					context.delete(channel)
				}
				do {
					try context.save()
				} catch {
					Logger.data.error("Failed to clear existing channels from local app database: \(error.localizedDescription, privacy: .public)")
				}
			}
		} catch {
			Logger.data.error("Failed to find a node MyInfo to save these channels to: \(error.localizedDescription, privacy: .public)")
		}

	}

	func handleTextMessageAppPacket(_ packet: MeshPacket, session: RadioSession? = nil) async {
		guard let device = (session ?? activeConnection)?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to handle text message when no connected device.")
			return
		}

		await MeshPackets.shared.textMessageAppPacket(
			packet: packet,
			wantRangeTestPackets: (session ?? activeConnection)?.wantRangeTestPackets ?? false,
			connectedNode: deviceNum,
			appState: appState
		)

	}

	func storeAndForwardPacket(packet: MeshPacket, connectedNodeNum: Int64) {
		if let storeAndForwardMessage = try? StoreAndForward(serializedBytes: packet.decoded.payload) {
			// Handle each of the store and forward request / response messages
			switch storeAndForwardMessage.rr {
			case .unset:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerError:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerHeartbeat:
				/// When we get a router heartbeat we know there is a store and forward node on the network
				/// Check if it is the primary S&F Router and save the timestamp of the last heartbeat so that we can show the request message history menu item on node long press if the router has been seen recently
				if storeAndForwardMessage.heartbeat.secondary == 0 {

					guard let routerNode = getNodeInfo(id: Int64(packet.from), context: context) else {
						return
					}
					if routerNode.storeForwardConfig != nil {
						routerNode.storeForwardConfig?.enabled = true
						routerNode.storeForwardConfig?.isRouter = storeAndForwardMessage.heartbeat.secondary == 0
						routerNode.storeForwardConfig?.lastHeartbeat = Date()
					} else {
						let newConfig = StoreForwardConfigEntity()
						newConfig.enabled = true
						newConfig.isRouter = storeAndForwardMessage.heartbeat.secondary == 0
						newConfig.lastHeartbeat = Date()
						context.insert(newConfig)
						routerNode.storeForwardConfig = newConfig
					}

					do {
						try context.save()
					} catch {
						Logger.data.error("Save Store and Forward Router Error")
					}
				}
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerPing:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerPong:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerBusy:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerHistory:
				/// Set the Router History Last Request Value
				guard let routerNode = getNodeInfo(id: Int64(packet.from), context: context) else {
					return
				}
				if routerNode.storeForwardConfig != nil {
					routerNode.storeForwardConfig?.lastRequest = Int32(storeAndForwardMessage.history.lastRequest)
				} else {
					let newConfig = StoreForwardConfigEntity()
					newConfig.lastRequest = Int32(storeAndForwardMessage.history.lastRequest)
					context.insert(newConfig)
					routerNode.storeForwardConfig = newConfig
				}

				do {
					try context.save()
				} catch {
					Logger.data.error("Save Store and Forward Router Error")
				}
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerStats:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientError:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientHistory:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientStats:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientPing:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientPong:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .clientAbort:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .UNRECOGNIZED:
				Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
			case .routerTextDirect:
				Task {
					Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
					await MeshPackets.shared.textMessageAppPacket(
						packet: packet,
						wantRangeTestPackets: false,
						connectedNode: connectedNodeNum,
						storeForward: true,
						appState: appState
					)
				}
			case .routerTextBroadcast:
				Task {
					Logger.mesh.info("[Store & Forward] packet received from \(packet.from.toHex(), privacy: .public) — \(String(describing: storeAndForwardMessage.rr), privacy: .public)")
					await MeshPackets.shared.textMessageAppPacket(
						packet: packet,
						wantRangeTestPackets: false,
						connectedNode: connectedNodeNum,
						storeForward: true,
						appState: appState
					)
				}
			}
		}
	}

	func handleTraceRouteApp(_ packet: MeshPacket, session: RadioSession? = nil) {
		guard let device = (session ?? activeConnection)?.device, let deviceNum = device.num else {
			Logger.services.error("Attempt to handle trace route when no connected device.")
			return
		}

		if let routingMessage = try? RouteDiscovery(serializedBytes: packet.decoded.payload) {
			// Full responses only: a trace route response always carries the originating request id.
			// A zero request id means this is an in-flight request (or a request targeting us), which
			// we don't persist.
			guard packet.decoded.requestID != 0 else {
				Logger.mesh.info("🪧 Ignoring trace route request (no response) from \(packet.from.toHex(), privacy: .public)")
				return
			}

			// Resolve the originator (request sender) and target (responder). For routes we initiated
			// the originator is our connected node and a TraceRouteEntity already exists. For routes
			// observed on the mesh the response is addressed back to the original requester
			// (`packet.to`) and sent by the responder (`packet.from`); we create a new record for those.
			// A record only counts as "initiated by us" when we sent the request. Observed routes we
			// previously stored (and may now be re-seeing as a rebroadcast) are updated in place.
			let existingTraceRoute = getTraceRoute(id: Int64(packet.decoded.requestID), context: context)
			let initiatedByUs = existingTraceRoute?.sent == true
			let originatorNum: Int64
			let targetNum: Int64
			let traceRoute: TraceRouteEntity
			if initiatedByUs, let existingTraceRoute {
				traceRoute = existingTraceRoute
				originatorNum = deviceNum
				targetNum = existingTraceRoute.node?.num ?? Int64(packet.from)
			} else {
				if let existingTraceRoute {
					traceRoute = existingTraceRoute
				} else {
					traceRoute = TraceRouteEntity()
					context.insert(traceRoute)
					traceRoute.id = Int64(packet.decoded.requestID)
				}
				traceRoute.sent = false
				originatorNum = Int64(packet.to)
				targetNum = Int64(packet.from)
			}
			traceRoute.response = true
			traceRoute.fromNum = originatorNum
			traceRoute.toNum = targetNum

			// Used for display/position lookups. The `node` relationship stays set only for routes we
			// initiated; observed routes are surfaced in the global trace route log instead.
			let originatorNode = getNodeInfo(id: originatorNum, context: context)
			let targetNodeInfo = (initiatedByUs ? existingTraceRoute?.node : nil) ?? getNodeInfo(id: targetNum, context: context)

			// Reprocessing an existing record (e.g. a rebroadcast we re-observe): drop the previous
			// hops before rebuilding so we don't accumulate orphaned/duplicate hop rows.
			for hop in traceRoute.hops {
				context.delete(hop)
			}

			var hopNodes: [TraceRouteHopEntity] = []
			let connectedHop = TraceRouteHopEntity()
			context.insert(connectedHop)
			connectedHop.time = Date()
			connectedHop.num = originatorNum
			connectedHop.name = originatorNode?.user?.longName ?? "???"
			connectedHop.index = 0
			// If nil, set to unknown, INT8_MIN (-128) then divide by 4
			connectedHop.snr = Float(routingMessage.snrBack.last ?? -128) / 4
			var routeString = "\(originatorNode?.user?.longName ?? "???") --> "
			hopNodes.append(connectedHop)
			traceRoute.hopsTowards = Int32(routingMessage.route.count)
			for (index, node) in routingMessage.route.enumerated() {
				var hopNode = getNodeInfo(id: Int64(node), context: context)
				if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
					hopNode = findOrCreateNode(num: Int64(node), context: context)
				}
				let traceRouteHop = TraceRouteHopEntity()
				context.insert(traceRouteHop)
				traceRouteHop.time = Date()
				if routingMessage.snrTowards.count >= index + 1 {
					traceRouteHop.snr = Float(routingMessage.snrTowards[index]) / 4
				} else {
					// If no snr in route, set unknown
					traceRouteHop.snr = -32
				}
				traceRouteHop.num = hopNode?.num ?? 0
				traceRouteHop.index = Int32(index + 1)
				if hopNode != nil {
					if packet.rxTime > 0 {
						hopNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
					}
				}
				hopNodes.append(traceRouteHop)

				let hopName = hopNode?.user?.longName ?? (node == 4294967295 ? "Repeater" : String(hopNode?.num.toHex() ?? "Unknown".localized))
				let mqttLabel = hopNode?.viaMqtt ?? false ? "MQTT " : ""
				let snrLabel = (traceRouteHop.snr != -32) ? String(traceRouteHop.snr) : "unknown ".localized
				routeString += "\(hopName) \(mqttLabel)(\(snrLabel)dB) --> "
			}
			let destinationHop = TraceRouteHopEntity()
			context.insert(destinationHop)
			destinationHop.name = targetNodeInfo?.user?.longName ?? "Unknown".localized
			destinationHop.time = Date()
			// If nil, set to unknown, INT8_MIN (-128) then divide by 4
			destinationHop.snr = Float(routingMessage.snrTowards.last ?? -128) / 4
			destinationHop.num = targetNum
			destinationHop.index = Int32(routingMessage.route.count + 1)
			hopNodes.append(destinationHop)
			/// Add the destination node to the end of the route towards string and the beginning of the route back string
			routeString += "\(targetNodeInfo?.user?.longName ?? "Unknown".localized) \(targetNum.toHex()) (\(destinationHop.snr != -32 ? String(destinationHop.snr) : "unknown ".localized)dB)"
			traceRoute.routeText = routeString
			// Default to -1 only fill in if routeBack is valid below
			traceRoute.hopsBack = -1
			// Only if hopStart is set and there is an SNR entry
			if packet.hopStart > 0 && routingMessage.snrBack.count > 0 {
				traceRoute.hopsBack = Int32(routingMessage.routeBack.count)
				var routeBackString = "\(targetNodeInfo?.user?.longName ?? "Unknown".localized) \(targetNum.toHex()) --> "
				for (index, node) in routingMessage.routeBack.enumerated() {
					var hopNode = getNodeInfo(id: Int64(node), context: context)
					if hopNode == nil && hopNode?.num ?? 0 > 0 && node != 4294967295 {
						hopNode = findOrCreateNode(num: Int64(node), context: context)
					}
					let traceRouteHop = TraceRouteHopEntity()
					context.insert(traceRouteHop)
					traceRouteHop.time = Date()
					traceRouteHop.back = true
					if routingMessage.snrBack.count >= index + 1 {
						traceRouteHop.snr = Float(routingMessage.snrBack[index]) / 4
					} else {
						// If no snr in route, set to unknown
						traceRouteHop.snr = -32
					}
					traceRouteHop.num = hopNode?.num ?? 0
					traceRouteHop.index = Int32(index)
					if hopNode != nil {
						if packet.rxTime > 0 {
							hopNode?.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
						}
					}
					hopNodes.append(traceRouteHop)

					let hopName = hopNode?.user?.longName ?? (node == 4294967295 ? "Repeater" : String(hopNode?.num.toHex() ?? "Unknown".localized))
					let mqttLabel = hopNode?.viaMqtt ?? false ? "MQTT " : ""
					let snrLabel = (traceRouteHop.snr != -32) ? String(traceRouteHop.snr) : "unknown ".localized
					routeBackString += "\(hopName) \(mqttLabel)(\(snrLabel)dB) --> "
				}
				// If nil, set to unknown, INT8_MIN (-128) then divide by 4
				let snrBackLast = Float(routingMessage.snrBack.last ?? -128) / 4
				routeBackString += "\(originatorNode?.user?.longName ?? originatorNum.toHex()) (\(snrBackLast != -32 ? String(snrBackLast) : "unknown ".localized)dB)"
				traceRoute.routeBackText = routeBackString
			}
			traceRoute.hops = hopNodes
			traceRoute.time = Date()

			// Snapshot each involved node's current position so the route can later be mapped using
			// the positions nodes had when the trace route ran, rather than wherever they've drifted
			// to since. One snapshot per unique node num (originator, target, and every hop).
			snapshotTraceRoutePositions(for: traceRoute, packet: packet, routingMessage: routingMessage)

			// Only notify for trace routes we initiated; observed routes shouldn't generate alerts.
			if traceRoute.sent {
				let manager = LocalNotificationManager()
				manager.notifications = [
					Notification(
						id: (UUID().uuidString),
						title: "Traceroute Complete",
						subtitle: "TR received back from \(destinationHop.name ?? "unknown")",
						content: "Hops from: \(traceRoute.hopsTowards), Hops back: \(traceRoute.hopsBack)\n\(traceRoute.routeText ?? "Unknown".localized)\n\(traceRoute.routeBackText ?? "Unknown".localized)",
						target: "nodes",
						path: "meshtastic:///nodes?nodenum=\(traceRoute.node?.num ?? targetNum)"
					)
				]
				manager.schedule()
			}

			do {
				try context.save()
				Logger.data.info("💾 Saved Trace Route")
			} catch {
				let nsError = error as NSError
				Logger.data.error("Error Updating Core Data TraceRouteHop: \(nsError, privacy: .public)")
			}
			let logString = String.localizedStringWithFormat("Trace Route request returned: %@".localized, routeString)
			Logger.mesh.info("🪧 \(logString, privacy: .public)")
		}
	}

	/// Captures a point-in-time snapshot of the current position of every node involved in a trace
	/// route (originator, target, and all forward/return hops), deduplicated by node num. Rebuilds
	/// from scratch so reprocessing a rebroadcast doesn't accumulate stale snapshots.
	private func snapshotTraceRoutePositions(for traceRoute: TraceRouteEntity, packet: MeshPacket, routingMessage: RouteDiscovery) {
		for existing in traceRoute.nodePositions {
			context.delete(existing)
		}

		// 0xFFFFFFFF is the "unknown node" sentinel used for repeater hops — skip it.
		let broadcastNum: UInt32 = 4294967295
		var nums = Set<Int64>([traceRoute.fromNum, traceRoute.toNum])
		for node in routingMessage.route where node != broadcastNum { nums.insert(Int64(node)) }
		for node in routingMessage.routeBack where node != broadcastNum { nums.insert(Int64(node)) }
		nums = nums.filter { $0 > 0 }

		var snapshotted = false
		for num in nums {
			guard let node = getNodeInfo(id: num, context: context),
				  let position = node.latestPosition,
				  position.nodeCoordinate != nil else {
				continue
			}
			let snapshot = TraceRouteNodePositionEntity()
			context.insert(snapshot)
			snapshot.num = num
			snapshot.latitudeI = position.latitudeI
			snapshot.longitudeI = position.longitudeI
			snapshot.altitude = position.altitude
			snapshot.precisionBits = position.precisionBits
			snapshot.satsInView = position.satsInView
			snapshot.speed = position.speed
			snapshot.heading = position.heading
			snapshot.seqNo = position.seqNo
			snapshot.snr = position.snr
			snapshot.time = position.time
			snapshot.traceRoute = traceRoute
			snapshotted = true
		}
		traceRoute.hasPositions = snapshotted
	}
}
