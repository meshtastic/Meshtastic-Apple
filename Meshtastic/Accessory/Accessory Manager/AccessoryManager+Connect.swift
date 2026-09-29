//
//  AccessoryManager+Connect.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/24/25.
//

import Foundation
import OSLog
import SwiftData
import MeshtasticProtobufs
import CoreBluetooth

private let maxRetries = 2
private let retryDelay: Duration = .seconds(2)

/// One run of the connect steps for one radio (feature 021, T070). Holds the session Step 1
/// makes, so every later step works on that radio's session and connection rather than on
/// whichever radio is focused.
@MainActor
final class ConnectAttempt {
	let device: Device
	/// The focused radio's connect, which also does the app-wide work (preferred radio, update
	/// gate, Messages snapshot, stopping discovery, stale-node prune, phone position, remembered
	/// radios). Every connect is the focused radio's until other radios run these steps (T071).
	let isFocused: Bool
	var session: RadioSession?
	/// This radio's connection status while it connects. The manager's `state` shows the
	/// focused radio's (T071).
	var status: AccessoryManagerState = .connecting
	/// Runs the steps. A disconnect, a heartbeat timeout or a link error cancels it.
	var stepper: SequentialSteps?
	/// Set when the radio is disconnected while its connect is still waiting to start.
	var isCancelled = false
	/// Whether radios other than the backfill owner had observations before this radio's first
	/// packet, for the backfill before it joins (T230). Nil when no backfill owner is set.
	var othersObservedBeforeJoin: Bool?

	init(device: Device, isFocused: Bool = true) {
		self.device = device
		self.isFocused = isFocused
	}

	/// The session from Step 1. Throws if a later step runs without one.
	func requireSession() throws -> RadioSession {
		guard let session else {
			throw AccessoryError.connectionFailed("No connection to \(device.name)")
		}
		return session
	}
}

extension AccessoryManager {
	/// Connects `device` through the connect steps. `asFocused: false` connects it alongside the
	/// focused radio (`connectAdditionalRadio`), with the same steps and without the app-wide work;
	/// that connect throws when it fails, and `connectTimeout` bounds its transport connect.
	func connect(
		to device: Device,
		withConnection: Connection? = nil,
		wantConfig: Bool = true,
		wantDatabase: Bool = true,
		versionCheck: Bool = true,
		refreshDeviceHardwareFromAPI: Bool = false,
		retries: Int? = nil,
		asFocused: Bool = true,
		connectTimeout: Duration? = nil
	) async throws {
		Logger.transport.info("AccessoryManager.connect(to: \(device.name, privacy: .public), withConnection: \(withConnection != nil), wantConfig: \(wantConfig), wantDatabase: \(wantDatabase), versionCheck: \(versionCheck), refreshDeviceHardwareFromAPI: \(refreshDeviceHardwareFromAPI), focused: \(asFocused))")
		// Prevent new connection if one is active
		if asFocused, activeConnection != nil {
			throw AccessoryError.connectionFailed("Already connected to a device")
		}
		if !asFocused, additionalRadios[device.id] != nil {
			throw AccessoryError.connectionFailed("This radio is already connected")
		}
		// One connect per radio at a time, focused or not (T152). A focused connect waiting at the
		// handshake gate doesn't show as connecting yet, so discovery or a restore could start a
		// second one for the same radio.
		if let existing = connectAttempts[device.id], !existing.isCancelled {
			throw AccessoryError.connectionFailed("This radio is already connecting")
		}
		
		guard let transport = transportForType(device.transportType) else {
			throw AccessoryError.connectionFailed("No transport for type")
		}

		let attempt = ConnectAttempt(device: device, isFocused: asFocused)
		// Runs last, after the attempt is gone: an Unlock or Update waiting on this connect, or
		// on the focused radio's, can take the focus now (T148, T179).
		defer { retryPendingAttentionFocusSoon() }
		connectAttempts[device.id] = attempt
		defer {
			if connectAttempts[device.id] === attempt {
				connectAttempts.removeValue(forKey: device.id)
				// A radio whose connect ends is ready now (`linkState(ofRadio:)`); observers such as
				// the discovery scan learn it from this, not from the next unrelated change (T180).
				objectWillChange.send()
			}
		}

		// Feature 021 (T064): one handshake at a time across every radio. Step 7 recycles the
		// ingest actor, which must not land in the middle of another radio's node dump.
		let cancelGeneration = connectCancelGeneration
		if handshakeGate.isBusy {
			Logger.transport.info("🔗 [Connect] Waiting for another radio's handshake to finish")
			updateDevice(deviceId: device.id, key: \.connectionState, value: .connecting)
		}
		await handshakeGate.acquire()
		defer { handshakeGate.release() }
		if (asFocused && connectCancelGeneration != cancelGeneration) || attempt.isCancelled {
			updateDevice(deviceId: device.id, key: \.connectionState, value: .disconnected)
			throw AccessoryError.connectionFailed("Connection cancelled")
		}
		if asFocused, activeConnection != nil {
			throw AccessoryError.connectionFailed("Already connected to a device")
		}
		if !asFocused, activeConnection == nil || !canConnectAnotherRadio {
			updateDevice(deviceId: device.id, key: \.connectionState, value: .disconnected)
			throw AccessoryError.connectionFailed("No longer room for this radio")
		}
		
		if attempt.isFocused {
			// Clear any errors and stale state from last connection
			lastConnectionError = nil
			firmwareUpdateRequired = false
			self.activeDeviceNum = nil
			packetsSent = 0
			packetsReceived = 0

			self.allowDisconnect = true
			self.userRequestedConnectionCancellation = false
		} else {
			radioConnectErrors.removeValue(forKey: device.id)
		}

		// On a first-ever BLE connection, iOS presents the pairing PIN sheet during
		// characteristic subscription (Step 1). The user needs time to read and type a
		// 6-digit PIN, so give the connect step a long window in that case. Already-bonded
		// peripherals (and non-BLE transports) keep the fast timeout so a dead/out-of-range
		// radio still fails quickly on reconnect.
		// One-time migration: seed pairedPeripheralIds from the legacy preferredPeripheralId so
		// users upgrading to this build (empty pairedPeripheralIds) don't pay the long pairing
		// window on the first reconnect to a radio they already paired before. After this runs
		// once, the preferred-peripheral fallback is never consulted again — the remember/forget
		// lifecycle in BLEConnection becomes the sole source of truth. That way a bond the user
		// later removes (e.g. via iOS Settings > Bluetooth) self-heals back to the long pairing
		// window instead of being pinned to the fast reconnect timeout forever.
		if !UserDefaults.migratedPreferredPeripheralPairing {
			UserDefaults.migratedPreferredPeripheralPairing = true
			if let preferredUUID = UUID(uuidString: PreferredRadio.peripheralId) {
				UserDefaults.rememberPairedPeripheral(preferredUUID)
			}
		}
		let knownBonded = UserDefaults.isPairedPeripheral(device.id)
		let isFirstTimeBLEBond = device.transportType == .ble && !knownBonded
		let connectStepTimeout: Duration = isFirstTimeBLEBond ? .seconds(90) : .seconds(5)

		// Prepare to connect
		attempt.stepper = connectSteps(
			attempt,
			transport: transport,
			withConnection: withConnection,
			wantConfig: wantConfig,
			wantDatabase: wantDatabase,
			versionCheck: versionCheck,
			refreshDeviceHardwareFromAPI: refreshDeviceHardwareFromAPI,
			retries: retries,
			connectTimeout: connectTimeout,
			connectStepTimeout: connectStepTimeout
		)

		if attempt.isFocused {
			self.connectionStepper = attempt.stepper
		}

		// Run the connection process
		do {
			try await attempt.stepper?.run()
			Logger.transport.debug("🔗 [Connect] ConnectionStepper completed.")
			// The scan pause covers the whole handshake — pairing happens during the
			// notify subscription, after the link comes up — so resume only now that
			// every step finished. Failed attempts resume via connectionDidDisconnect.
			if let bleTransport = transportForType(.ble) as? BLETransport {
				await bleTransport.resumeScanningAfterConnectionEstablished(for: UUID(uuidString: device.identifier) ?? device.id)
			}
			// Feature 021 (T063): remember this connection, then bring back the radios that were
			// connected alongside it. Their attempts queue on the handshake gate behind this one.
			if attempt.isFocused, restoreDisplacedPreferred == device.id {
				// It came back as the focused radio itself: nothing left to give back (T200).
				restoreDisplacedPreferred = nil
			}
			if attempt.isFocused, let focused = activeConnection, let nodeNum = focused.nodeNum {
				await MeshPackets.shared.noteRadioConnected(nodeNum: nodeNum, transport: focused.device.transportType, autoConnect: nil)
				await reconnectRememberedRadios()
			} else if !attempt.isFocused, let session = attempt.session {
				// Remembered, so it comes back next time alongside the focused radio.
				if let nodeNum = session.nodeNum {
					await MeshPackets.shared.noteRadioConnected(nodeNum: nodeNum, transport: device.transportType, autoConnect: true)
				}
				WatchSessionManager.shared.sendNodesToWatch()
			}
		} catch {
			Logger.transport.error("🔗 [Connect] Error returned by connectionStepper: \(error, privacy: .public)")
			attempt.stepper = nil
			try await self.cleanUpAfterFailedConnect(attempt)
			guard attempt.isFocused else {
				// The caller (the reconnect loop, the Connect tab) decides what to do next.
				radioConnectErrors[device.id] = error
				throw error
			}
			self.lastConnectionError = error
			self.connectionStepper = nil
			return
		}
		
		// All done, one way or another, clean up
		attempt.stepper = nil
		if attempt.isFocused {
			self.connectionStepper = nil
		}
	}

	/// The connect steps for one radio (T070/T071): the same for every radio, with the app-wide
	/// work only in the focused radio's (`attempt.isFocused`).
	// swiftlint:disable:next function_parameter_count
	private func connectSteps(
		_ attempt: ConnectAttempt,
		transport: any Transport,
		withConnection: Connection?,
		wantConfig: Bool,
		wantDatabase: Bool,
		versionCheck: Bool,
		refreshDeviceHardwareFromAPI: Bool,
		retries: Int?,
		connectTimeout: Duration?,
		connectStepTimeout: Duration
	) -> SequentialSteps {
		let device = attempt.device
		return SequentialSteps(maxRetries: retries ?? maxRetries, retryDelay: retryDelay) {
			
			// Step 0
			Step { @MainActor retryAttempt in
				Logger.transport.info("🔗👟 [Connect] Starting connection to \(device.id, privacy: .public)")
				if retryAttempt > 0 {
					try await self.cleanUpBeforeRetry(attempt) // clean-up before retries.
					self.setStatus(.retrying(attempt: retryAttempt + 1, maxAttempts: retries ?? maxRetries), for: attempt)
					if attempt.isFocused {
						self.allowDisconnect = true
					}
				} else {
					self.setStatus(.connecting, for: attempt)
				}
				self.updateDevice(deviceId: device.id, key: \.connectionState, value: .connecting)
				// Asked before the event stream starts: the packets this radio queued arrive with its
				// config and write its observations before Step 3c gets to the backfill (T230). The
				// store's own radio, known by its number, doesn't need it.
				if retryAttempt == 0 {
					let owner = BackfillOwner.current().nodeNum
					if owner != 0, device.num != owner {
						attempt.othersObservedBeforeJoin = await MeshPackets.shared.otherRadiosHaveObservations(than: owner)
					}
				}
			}
			
			// Step 1: Setup the connection
			Step(timeout: connectStepTimeout) { @MainActor _ in
				Logger.transport.info("🔗👟[Connect] Step 1: connection to \(device.id, privacy: .public)")
				do {
					let connection: Connection
					if let providedConnection = withConnection {
						connection = providedConnection
					} else if attempt.isFocused {
						connection = try await transport.connect(to: device)
					} else {
						connection = try await self.connectTransport(transport, to: device, within: connectTimeout)
						// The connect can take a while (BLE waits for the radio). Re-check what it assumed.
						guard self.activeConnection != nil, self.additionalRadios[device.id] == nil, self.canConnectAnotherRadio else {
							try? await connection.disconnect(withError: nil, shouldReconnect: false)
							throw AccessoryError.connectionFailed("No longer room for this radio")
						}
					}
					let eventStream = try await connection.connect()
					self.setStatus(.communicating, for: attempt)
					// Every event is tagged with the session it came from, so a late event from an
					// earlier attempt's connection is never handled against this one.
					let session = RadioSession(device: device, connection: connection)
					session.eventTask = Task {
						for await event in eventStream {
							await self.didReceive(event, from: session)
						}
						Logger.transport.info("[Accessory] Event stream closed")
					}
					attempt.session = session
					if attempt.isFocused {
						self.activeConnection = session
						self.activeDeviceNum = device.num
					} else {
						// Registered before its first event is handled, so its events go to its own
						// handling rather than being dropped as a stale connection's.
						self.additionalRadios[device.id] = session
					}
					// The mesh-traffic monitor (map flyover gate) self-starts its decay timer on the
					// first inbound packet and is cleared by Step 0's closeConnection() reset(), so
					// there's no explicit start to make here — it stays correct across connect retries.
				} catch let error where BLEConnection.terminatesConnectRetries(error) {
					// A lost bond cannot be fixed by retrying or reconnecting — the user has to
					// forget the device in iOS Settings. The old catch matched only the raw CBError,
					// but the transport maps that into AccessoryError.bondLost before throwing, so
					// the mapped error fell through to retryAll and looped. Kill auto-reconnect
					// before cancelling or discovery immediately starts the loop again.
					self.shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
					self.autoReconnectSuspendedForSession = true
					self.lastConnectionError = AccessoryError.bondLost
					await attempt.stepper?.cancelCurrentlyExecutingStep(withError: AccessoryError.bondLost, cancelFullProcess: true)
				}
			}
			
			// Step 2: Send Heartbeat before wantConfig (config)
			Step { @MainActor _ in
				guard wantConfig else {
					Logger.transport.info("👟 [Connect] Step 2: wantConfig = false, skipping heartbeat")
					return
				}
				Logger.transport.info("💓👟 [Connect] Step 2: Send heartbeat")
				try await self.sendHeartbeat(on: attempt.requireSession())
			}
			
			// Step 3: Send WantConfig (config)
			Step(timeout: .seconds(30)) { @MainActor _ in
				guard wantConfig else {
					Logger.transport.info("👟 [Connect] Step 4: wantConfig = false, skipping wantConfig")
					return
				}
				Logger.transport.info("🔗👟 [Connect] Step 3: Send wantConfig (config)")
				try await self.sendWantConfig(on: attempt.requireSession())
				// Always refresh the bundled device catalog so hardware metadata is present after any
				// database clear, regardless of who initiated the connect. Metadata only: this call is
				// awaited inside a 30s Step budget, so it must stay local (issue #2196). Device images
				// and the "I want one" msh.to links are network-backed and are restored by the detached
				// pass below instead.
				// The catalog is app-wide, so the focused radio's connect refreshes it.
				if attempt.isFocused {
					do {
						Logger.transport.info("🔗👟 [Connect] Step 3a: Refresh bundled Meshtastic device hardware data")
						try await MeshtasticAPI.shared.refreshBundledDevicesData()
						Logger.services.info("✅ [MeshtasticAPI] Refreshed bundled device hardware data after config completion")
					} catch {
						Logger.services.warning("Failed to refresh bundled device hardware data after config completion: \(error.localizedDescription, privacy: .public)")
					}
				}

				// Step 3b: images and msh.to links. `clearDatabase` batch-deletes
				// DeviceHardwareImageEntity and DeviceLinkEntity, and a NodeDB/factory reset or a
				// device switch clears mid-session and then reconnects — so launch-time population is
				// already gone by the time we get here and something on the connect path has to
				// restore them. Detached on purpose: both halves hit the network and must never be
				// awaited inside this Step's 30s budget. `refreshDeviceHardwareFromAPI` defaults to
				// false, so the bundle-only pass is what runs on a normal reconnect; it resolves
				// images from the app bundle and msh.to links from the bundled urls.json.
				Logger.transport.info("🔗👟 [Connect] Step 3b: Refresh device images and msh.to links")
				// Held on the manager so closeConnection can cancel it: on a captive portal the pass's
				// image HEADs would otherwise hang ~60s past a disconnect. A prior pass from a rapid
				// reconnect is cancelled before the new one replaces the handle.
				// App-wide, so the focused radio's connect runs it.
				if attempt.isFocused {
					self.deviceRefreshTask?.cancel()
					self.deviceRefreshTask = Task.detached(priority: .utility) {
						if refreshDeviceHardwareFromAPI {
							await MeshtasticAPI.shared.refreshDevicesPreferringAPI()
						} else {
							await MeshtasticAPI.shared.refreshDeviceImagesAndLinks()
						}
					}
				}
			}
			
			// Step 3c: rows from before feature 021 go to the store's radio before this radio's node
			// DB joins them (T186, T193, T203). Its own step once the config is in and the radio's
			// node number known: no step timeout runs here, and the radio's event loop isn't held
			// up meanwhile (T210). The store's own radio doesn't wait.
			Step { @MainActor _ in
				let session = try attempt.requireSession()
				guard let radioNum = session.nodeNum else { return }
				await self.backfillBeforeAnotherRadioJoins(radioNum: radioNum, name: session.device.longName ?? session.device.name, othersObserved: attempt.othersObservedBeforeJoin)
			}

			// Step 4: Send Heartbeat before wantConfig (database)
			Step { @MainActor _ in
				guard wantDatabase else {
					Logger.transport.info("👟 [Connect] Step 4: wantDatabase = false, skipping heartbeat")
					return
				}
				Logger.transport.info("💓 [Connect] Step 4: Send heartbeat")
				try await self.sendHeartbeat(on: attempt.requireSession())
			}
			
			// Step 5: Send WantConfig (database)
			Step(timeout: .seconds(10.0), onFailure: .retryStep(attempts: 3)) { @MainActor _ in
				// Recorded for every focused connect, a restore without a handshake too (T240): it's
				// the focused radio either way.
				if attempt.isFocused {
					Logger.transport.info("🔗 Saving preferredPeripheralId: \(device.id.uuidString)")
					PreferredRadio.peripheralId = device.id.uuidString
					if !wantConfig, let nodeNum = device.num {
						// No MyInfo comes without the config handshake; the restore found the number.
						PreferredRadio.nodeNum = nodeNum
					}
					self.radiosFocusedThisRun.insert(device.id.uuidString)
					// A radio connected as the focused one is also the one to connect first (T212);
					// a restore that passed over that radio sets its override again afterwards.
					PreferredRadio.connectFirstOverride = nil
				}
				guard wantDatabase else {
					Logger.transport.info("👟 [Connect] Step 5: wantDatabase = false, skipping wantDatabase")
					return
				}
				// A retry of this step must never re-request the dump while one is already
				// streaming: the radio would restart the node DB from the top and the two dumps
				// would interleave (slow connects, duplicate processing). If nodes are already
				// arriving, treat the request as delivered and let Step 5a's gate do the waiting.
				let session = try attempt.requireSession()
				if case .retrievingDatabase = attempt.status, session.databaseNodeCount > 0 {
					Logger.transport.info("🔗👟 [Connect] Step 5: node dump already streaming (\(session.databaseNodeCount) nodes) — not re-requesting")
					return
				}
				Logger.transport.info("🔗👟 [Connect] Step 5: Send wantConfig (database)")
				// Counted from here: the config handshake before it also carries the radio's own node.
				session.databaseNodeCount = 0
				self.setStatus(.retrievingDatabase(nodeCount: 0), for: attempt)
				if attempt.isFocused {
					self.allowDisconnect = true
				}

				try await self.sendWantDatabase(on: attempt.requireSession())
			}
			
			// Step 5a: Wait for end of WantConfig (database)
			// Bounded like its sibling steps: without a timeout, a malicious/misbehaving radio
			// that completes config but never sends the database-complete nonce would wedge the
			// connect flow in .retrievingDatabase forever (no watchdog until Step 8). 120s is
			// generous for a large legitimate node-DB dump.
			Step(timeout: .seconds(120)) { @MainActor _ in
				guard wantDatabase else {
					Logger.transport.info("👟 [Connect] Step 4: wantDatabase = false, skipping waitForWantDatabase")
					return
				}
				Logger.transport.info("🔗👟 [Connect] Step 5a: Wait for the final database")
				try await self.waitForWantDatabaseResponse(on: attempt.requireSession())
			}
			
			// Step 6: Version check
			Step { @MainActor _ in
				guard versionCheck else {
					Logger.transport.info("👟 [Connect] Step 6: versionCheck = false, skipping version check")
					return
				}
				Logger.transport.info("🔗👟 [Connect] Step 6: Version check")
				try self.checkConnectedFirmware(attempt)
			}
			
			// Step 7: Update UI and status to connected
			Step { @MainActor _ in
				Logger.transport.info("🔗👟 [Connect] Step 7: Update Time, UI and status")
				// Send time to device
				try? await self.sendTime(on: attempt.requireSession())
				
				// Allow disconnect here too
				if attempt.isFocused {
					self.allowDisconnect = true
				}

				// We have an active connection
				self.updateDevice(deviceId: device.id, key: \.connectionState, value: .connected)
				self.setStatus(.subscribed, for: attempt)

				// Release accumulated ModelContext memory from DB retrieval. Other radios keep
				// receiving meanwhile, so the retired actor keeps saving what they had in flight.
				await MeshPackets.shared.flushDebouncedSaves()
				MeshPackets.recreateShared(invalidatingPrevious: false)
				self.ingestPacketsSinceRecycle = 0
				
				// If we successfully connected to a manual connection, then save it to the list
				// Remember, Device is a value type (struct) so don't use use `device` here, thats
				// The value at the instantiation of the connect process.  We want the currently
				// updated device object in `activeConnection` with its additonal metadata from
				// NodeInfo packets.
				if let radioDevice = attempt.session?.device, radioDevice.isManualConnection {
					ManualConnectionList.shared.insert(device: radioDevice)
				}

				// Refresh the Messages sharing snapshot here rather than only off the config and
				// database completions: a background BLE restoration of an already-connected
				// peripheral reconnects with wantConfig and wantDatabase false (BLETransport's
				// `.connected` case), so neither completion fires and the extension is left
				// reporting no radio. Every connect path reaches this step.
				// The snapshot and the update notice are the focused radio's (T106, T073).
				if attempt.isFocused {
					if let activeDeviceNum = self.activeDeviceNum {
						MeshShareSnapshotBuilder.refresh(nodeNum: activeDeviceNum, context: self.context)
					}

					// Best-effort: the notifier bounds stale API refresh and cannot roll back a completed connect.
					await FirmwareUpdateNotifier.notifyIfNeeded(accessoryManager: self)
				}
			}
			
			// Step 8: Update UI and status to connected
			Step { @MainActor _ in
				Logger.transport.debug("🔗👟 [Connect] Step 8: Initialize MQTT and Location Provider")
				let session = try attempt.requireSession()
				if attempt.isFocused {
					self.stopDiscovery()
					// Prune stale nodes now that the dump is in, instead of at the head of
					// sendWantConfig where the fetch+delete+save serialized ahead of the whole
					// handshake on the ingestion actor. Post-dump lastHeard values also make the
					// pruning decisions more accurate.
					_ = await MeshPackets.shared.clearStaleNodes(nodeExpireDays: Int(UserDefaults.purgeStaleNodeDays))
				}
				// Every radio's own module settings and MQTT client proxy (T071c).
				self.applyModuleSettings(session)
				Task { await self.startMqtt(session) }
				if attempt.isFocused {
					self.initializeUnreadBadges()
					// One loop shares the phone's position with every connected radio (T101).
					self.initializeLocationProvider()
				}
				if transport.requiresPeriodicHeartbeat {
					await self.setupPeriodicHeartbeat(on: session)
				}
				
				let connectionWasRestored = (withConnection != nil)
				Logger.datadog.action(.connect(firmwareVersion: self.reportedFirmwareVersion(for: session.device),
												transportType: session.device.transportType.rawValue,
												hardwareModel: session.device.hardwareModel,
												nodes: session.expectedNodeDBSize,
												connectionRestored: connectionWasRestored,
												additionalRadio: !attempt.isFocused))
			}
				}
	}

	/// Connect Step 6: the radio's firmware version.
	private func checkConnectedFirmware(_ attempt: ConnectAttempt) throws {
		guard let firmwareVersion = attempt.session?.device.firmwareVersion else {
			Logger.transport.error("🔗 [Connect] Firmware version not available for device \(attempt.device.name, privacy: .public)")
			throw AccessoryError.connectionFailed("Firmware version not available")
		}

		if firmwareVersion.lastIndex(of: ".") == nil {
			throw AccessoryError.versionMismatch("🚨" + "Update Your Firmware".localized)
		}

		// Below-minimum firmware keeps its connection on every radio (D-17). The focused radio
		// shows the update gate; another radio is marked as needing an update, which prompts the
		// user by name (T073).
		if !attempt.isFocused, let session = attempt.session, let attention = firmwareAttention(for: session) {
			setAttention(attention, for: session)
		}
		if attempt.isFocused {
			// Below-minimum firmware keeps its connection. Throwing here used to retry the
			// whole process and then disconnect, which left the user no way to update the
			// radio from the app. The gate in ContentView blocks everything but the
			// firmware update screen instead.
			firmwareUpdateRequired = !checkIsVersionSupported(forVersion: minimumVersion)
		}
	}

	/// Sets `attempt`'s status, and the manager's too when it's the focused radio's (T071).
	func setStatus(_ status: AccessoryManagerState, for attempt: ConnectAttempt) {
		attempt.status = status
		if attempt.isFocused {
			updateState(status)
		}
	}

	/// Step 0 before a retry: the previous try's connection goes. For the focused radio that's
	/// the whole `closeConnection()`, as before.
	private func cleanUpBeforeRetry(_ attempt: ConnectAttempt) async throws {
		if attempt.isFocused {
			try await closeConnection()
		} else if let session = attempt.session {
			attempt.session = nil
			if additionalRadios[session.device.id] === session {
				additionalRadios.removeValue(forKey: session.device.id)
			}
			retiredAdditionalSessionIDs.insert(session.id)
			await tearDown(session)
			try? await session.connection.disconnect(withError: nil, shouldReconnect: false)
		}
	}

	/// After the steps gave up.
	private func cleanUpAfterFailedConnect(_ attempt: ConnectAttempt) async throws {
		if attempt.isFocused {
			try await closeConnection()
			updateState(.discovering)
		} else {
			try await cleanUpBeforeRetry(attempt)
			updateDevice(deviceId: attempt.device.id, key: \.connectionState, value: .disconnected)
		}
	}
	/// The firmware version this node last reported, from its own stored metadata.
	///
	/// Per node on purpose: an app-wide stored version would report one radio's firmware against
	/// another when a second radio connects before its metadata arrives.
	func storedFirmwareVersion(for nodeNum: Int64?) -> String? {
		guard let nodeNum else { return nil }
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		guard let stored = try? context.fetch(descriptor).first?.metadata?.firmwareVersion,
			  !stored.isEmpty else { return nil }
		return stored
	}

	/// `device`'s firmware version as the `connect` action reports it, without the build suffix.
	/// On a reconnect the device metadata can land after the connection is up, so
	/// `device.firmwareVersion` is briefly nil. Fall back to what this node last told us
	/// (`storedFirmwareVersion(for:)`).
	func reportedFirmwareVersion(for device: Device) -> String? {
		guard let firmwareVersion = device.firmwareVersion ?? storedFirmwareVersion(for: device.num) else {
			return nil
		}
		guard let lastDotIndex = firmwareVersion.lastIndex(of: ".") else {
			return firmwareVersion
		}
		return String(firmwareVersion[...lastDotIndex].dropLast())
	}
}

// Sequentially stepped tasks
typealias Step = SequentialSteps.Step
actor SequentialSteps {
	
	typealias StepClosure = @Sendable (_ retryAttempt: Int) async throws -> Void
	
	enum FailureBehavior {
		case fail
		case retryStep(attempts: Int)
		case retryAll
	}
	
	struct Step {
		let timeout: Duration?
		let failureBehavior: FailureBehavior
		let operation: StepClosure
		
		init(timeout: Duration? = nil, onFailure: FailureBehavior = .retryAll, operation: @escaping StepClosure) {
			self.timeout = timeout
			self.failureBehavior = onFailure
			self.operation = operation
		}
	}
	
	private enum SequentialStepError: Error, LocalizedError {
		case timeout(stepNumber: Int, afterWaiting: Duration)
		
		var errorDescription: String? {
			switch self {
			case .timeout(let stepNumber, let afterWaiting):
				return "Timeout after \(afterWaiting) waiting for step \(stepNumber)."
			}
		}
	}
	let steps: [Step]
	var currentlyExecutingStep: Task<Void, any Error>?
	var cancelled = false
	var maxRetries: Int
	var retryDelay: Duration
	var isRunning: Bool = false
	var externalError: Error?
	
	init(maxRetries: Int = 3, retryDelay: Duration = .seconds(3), @StepsBuilder _ builder: () -> [Step]) {
		self.maxRetries	= maxRetries
		self.retryDelay = retryDelay
		self.steps = builder()
	}
	
	func run() async throws {
		self.isRunning = true
		retryLoop: for attempt in 0..<maxRetries {
			for stepNumber in 0..<steps.count {
				if cancelled {
					throw externalError ?? CancellationError()
				}
				let currentStep = steps[stepNumber]
				let isRetry = (attempt > 0)
				if isRetry {
					try await Task.sleep(for: retryDelay)
				}
				do {
					let stepRetries = if case let .retryStep(attempts) = currentStep.failureBehavior, attempts > 0 { attempts } else { 1 }
					stepRetryLoop: for stepRetryAttempt in 0..<stepRetries {
						if stepRetryAttempt > 0 {
							Logger.transport.info("[Retry Step Loop] Retrying step \(stepNumber + 1) for the \(stepRetryAttempt + 1) time.")
							try await Task.sleep(for: retryDelay)
						}
						do {
							// Starting a new attempt for this step.
							if let duration = currentStep.timeout {
								// Execute this task with a timeout
								self.currentlyExecutingStep = executeWithTimeout(stepNumber: stepNumber, timeout: duration) {
									try await currentStep.operation(attempt)
								}
								try await self.currentlyExecutingStep!.value
							} else {
								// Execute this task without a timeout
								self.currentlyExecutingStep = Task {
									try await currentStep.operation(attempt)
								}
								try await self.currentlyExecutingStep!.value
							}
							break stepRetryLoop // Exit retry loop if successful
						} catch {
							if stepRetryAttempt == stepRetries - 1 {
								// If this is the last retry attempt, we throw the error to the outer loop
								throw error
							} else {
								switch error {
								case let SequentialStepError.timeout(stepNumber, afterWaiting):
									Logger.transport.info("[Inner Retry Step Loop] Sequential process timed out on step \(stepNumber) of \(stepRetries) after waiting \(afterWaiting)")
								case is CancellationError:
									if let externalError {
										// Something from the outside had an error which caused the cancellation of this step
										let errorToThrow = externalError
										self.externalError = nil
										throw errorToThrow
									}
									break stepRetryLoop
								default:
									Logger.transport.error("[Inner Retry Step Loop] Sequential process failed on step \(stepNumber) with error: \(error.localizedDescription, privacy: .public)")
								}
							}
						}
					}
				} catch {
					switch error {
					case let SequentialStepError.timeout(stepNumber, afterWaiting):
						Logger.transport.info("[Outer Step Retry Loop] Sequential process timed out on step \(stepNumber) after waiting \(afterWaiting)")
					default:
						Logger.transport.error("[Outer Step Retry Loop] Sequential process failed on step \(stepNumber) with error: \(error.localizedDescription, privacy: .public)")
					}
					switch currentStep.failureBehavior {
					case .retryAll, .retryStep:
						// TODO: we could have a .retryStepAndFail and a .retryStepAndContinue instead of just .retryStep to clarify the behavior here
						continue retryLoop
					case .fail:
						isRunning = false
						throw error
					}
				}
			}
			// We have finished all steps
			isRunning = false
			return
		}
		isRunning = false
		// return
		throw AccessoryError.tooManyRetries
	}
	
	func cancel() {
		cancelled = true
		self.currentlyExecutingStep?.cancel()
	}
	
	func cancelCurrentlyExecutingStep(withError: Error?, cancelFullProcess: Bool = false) {
		self.externalError = withError
		if cancelFullProcess {
			cancel()
		} else {
			self.currentlyExecutingStep?.cancel()
		}
	}
	
	func executeWithTimeout<ReturnType>(stepNumber: Int, timeout: Duration, operation: @escaping @Sendable () async throws -> ReturnType) -> Task<ReturnType, Error> {
		return Task {
			try await withThrowingTaskGroup(of: ReturnType.self) { group -> ReturnType in
				group.addTask(operation: operation)
				group.addTask {
					try await _Concurrency.Task.sleep(for: timeout)
					throw SequentialStepError.timeout(stepNumber: stepNumber, afterWaiting: timeout)
				}
				guard let success = try await group.next() else {
					throw SequentialStepError.timeout(stepNumber: stepNumber, afterWaiting: timeout)
				}
				group.cancelAll()
				return success
			}
		}
	}
	
	@resultBuilder
	struct StepsBuilder {
		static func buildBlock(_ components: Step...) -> [Step] {
			return components
		}
	}
}
