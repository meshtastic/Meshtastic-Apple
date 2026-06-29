//
//  Connect.swift
//  Meshtastic Apple
//
//  Copyright(c) Garth Vander Houwen 8/18/21.
//

import SwiftUI
import MapKit
@preconcurrency import SwiftData
import CoreLocation
import CoreBluetooth
import OSLog
import TipKit
#if canImport(ActivityKit)
import ActivityKit
#endif

struct Connect: View {
	
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.colorScheme) private var colorScheme
	@State var router: Router
	@State var node: NodeInfoEntity?
	/// Cached battery level for the connected node. Refreshed on an interval (see `.task`)
	/// rather than fetched in `body`, which re-ran a TelemetryEntity query on every render.
	@State private var connectedBatteryLevel: Int32?
	@State var isUnsetRegion = false
	@State var invalidFirmwareVersion = false
	@State var showSecurityVersionNag = false
#if !targetEnvironment(macCatalyst)
	@State var liveActivityStarted = false
#endif
	@ObservedObject var manualConnections = ManualConnectionList.shared
	@ObservedObject private var nymeaProvisioning = NymeaProvisioningManager.shared
	@Environment(\.scenePhase) private var scenePhase
	@State private var pendingNymeaDevice: NymeaDiscoveredDevice?
	@State private var isSwitchingRadio = false
	@State private var showingShutdownConfirm = false
	/// Stable identity of the node whose context menu opened the shutdown dialog, captured at tap
	/// time so the confirmation can't drift to a different node if the connection changes first.
	@State private var pendingShutdownNodeNum: Int64?

	private var sortedAvailableDevices: [Device] {
		accessoryManager.devices.sorted { lhs, rhs in
			let preferredId = UserDefaults.preferredPeripheralId
			let lhsIsPreferred = lhs.id.uuidString == preferredId
			let rhsIsPreferred = rhs.id.uuidString == preferredId

			if lhsIsPreferred != rhsIsPreferred {
				return lhsIsPreferred
			}

			return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
		}
	}

	/// The connected node, but only while it's still a live SwiftData object.
	///
	/// `node` is cached in `@State` and survives across connection state changes, so after a
	/// disconnect/reconnect or node switch — which recreate the ModelContext/container — the
	/// cached reference can become faulted or detached. Reading any real attribute on a faulted
	/// `@Model` traps (`_SD_get_faulting_backingdata` → `SIGTRAP`), and because the Connect tab
	/// is always mounted and re-renders on `accessoryManager` state changes, that trap fires
	/// during render. `modelContext` is safe metadata (nil on a detached/deleted object), so
	/// gating every read through this accessor prevents the crash. (Same guard pattern as #1944.)
	private var safeNode: NodeInfoEntity? {
		Connect.liveNode(node)
	}

	/// Returns `node` only while it is still a live SwiftData object (`modelContext != nil`),
	/// otherwise nil. Reading attributes on a faulted/detached `@Model` traps, so callers gate
	/// every read through this. Static + value-in/value-out so it can be unit-tested directly.
	static func liveNode(_ node: NodeInfoEntity?) -> NodeInfoEntity? {
		guard let node, node.modelContext != nil, !node.isDeleted else { return nil }
		return node
	}

	/// The user a shutdown should be sent to, or nil when the shutdown must be safely skipped.
	///
	/// Resolved at confirm time — never captured ahead of the dialog — so a faulted/detached
	/// `@Model` is gated by `liveNode` rather than trapping (the #2006 crash class). It also
	/// verifies the live node still matches `expectedNum`, the identity captured when the menu was
	/// opened: the dialog deliberately survives connection changes, so without this check a radio
	/// switch between the long-press and tapping "Shutdown Node?" would shut down the newly
	/// connected node instead of the one the user chose.
	static func shutdownTarget(for node: NodeInfoEntity?, expectedNum: Int64?) -> UserEntity? {
		guard let expectedNum, let live = liveNode(node), live.num == expectedNum else { return nil }
		return live.user
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				List {
					Section {
						if let connectedDevice = accessoryManager.activeConnection?.device,
						   accessoryManager.isConnected || accessoryManager.isConnecting {
							TipView(ConnectionTip(), arrowEdge: .bottom)
										.tipViewStyle(PersistentTipStyle())
								.tipBackground(colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground))
								.listRowSeparator(.hidden)
							VStack(alignment: .leading) {
								HStack {
									VStack(alignment: .center) {
										CircleText(text: safeNode?.user?.shortName?.addingVariationSelectors ?? "?", color: Color(UIColor(hex: UInt32(safeNode?.num ?? 0))), circleSize: 90)
											.padding(.trailing, 5)
										if let batteryLevel = connectedBatteryLevel {
											BatteryCompact(batteryLevel: batteryLevel, font: .caption, iconFont: .callout, color: .accentColor)
												.padding(.trailing, 5)
										}
									}
									.padding(.trailing)
									VStack(alignment: .leading) {
										if safeNode != nil {
											HStack {
												Text(connectedDevice.longName?.addingVariationSelectors ?? "Unknown".localized).font(.title2)
												if connectedDevice.wasRestored {
													Circle()
														.fill(Color.gray)
														.frame(width: 8, height: 8)
												}
											}
										}
										Text("Connection Name").font(.callout)+Text(": \(connectedDevice.name.addingVariationSelectors)")
											.font(.callout).foregroundColor(Color.gray)
										HStack(alignment: .firstTextBaseline) {
											TransportIcon(transportType: connectedDevice.transportType)
											if connectedDevice.transportType == .ble {
												connectedDevice.getSignalStrength().map { SignalStrengthIndicator(signalStrength: $0, width: 5, height: 20) }
											}
											Spacer()
										}
										.padding(0)
										if safeNode != nil {
											Text("Firmware Version").font(.callout)+Text(": \(safeNode?.metadata?.firmwareVersion ?? "Unknown".localized)")
												.font(.callout).foregroundColor(Color.gray)
										}
										if accessoryManager.firmwareEdition.isEvent {
											Text(accessoryManager.firmwareEdition.name)
												.font(.callout)
												.foregroundColor(.orange)
										}
										switch accessoryManager.state {
										case .subscribed:
											Text("Subscribed").font(.callout)
												.foregroundColor(.green)
										case .retrievingDatabase(let nodeCount):
											HStack {
												Image(systemName: "square.stack.3d.down.forward")
													.symbolRenderingMode(.multicolor)
													.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
													.foregroundColor(.teal)
												if let expectedNodeDBSize = accessoryManager.expectedNodeDBSize {
													if UIDevice.current.userInterfaceIdiom == .phone {
														VStack(alignment: .leading, spacing: 2.0) {
															Text("Retrieving nodes").font(.callout)
																.foregroundColor(.teal)
															ProgressView(value: Double(nodeCount), total: Double(expectedNodeDBSize))
														}
													} else {
														// iPad/Mac with more space, show progress bar AFTER the label
														HStack {
															Text("Retrieving nodes").font(.callout)
																.foregroundColor(.teal)
															ProgressView(value: Double(nodeCount), total: Double(expectedNodeDBSize))
														}
													}
													
												} else {
													Text("Retrieving nodes \(nodeCount)").font(.callout)
														.foregroundColor(.teal)
												}
											}
										case .communicating:
											HStack {
												Image(systemName: "square.stack.3d.down.forward")
													.symbolRenderingMode(.multicolor)
													.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
													.foregroundColor(.orange)
												Text("Communicating").font(.callout)
													.foregroundColor(.orange)
											}
										case .retrying(let attempt):
											HStack {
												Image(systemName: "square.stack.3d.down.forward")
													.symbolRenderingMode(.multicolor)
													.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
													.foregroundColor(.orange)
												Text("Retrying (attempt \(attempt))").font(.callout)
													.foregroundColor(.orange)
											}
										default:
											EmptyView()
										}
									}
								}
							}
							.font(.caption)
							.foregroundColor(Color.gray)
							.padding([.top])
							.swipeActions {
								if accessoryManager.allowDisconnect {
									Button(role: .destructive) {
										Task {
											try await accessoryManager.disconnect()
										}
									} label: {
										Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
									}
									.disabled(!accessoryManager.allowDisconnect)
								}
							}
							.contextMenu {
								
								if let node = safeNode {
									Label("\(String(node.num))", systemImage: "number")
#if !targetEnvironment(macCatalyst)
									if accessoryManager.state == .subscribed {
										Button {
											if !liveActivityStarted {
#if canImport(ActivityKit)
												Logger.services.info("Start live activity.")
												startNodeActivity()
#endif
											} else {
#if canImport(ActivityKit)
												Logger.services.info("Stop live activity.")
												endActivity()
#endif
											}
										} label: {
											Label("Mesh Live Activity", systemImage: liveActivityStarted ? "stop" : "play")
										}
									}
#endif
									if accessoryManager.allowDisconnect {
										Button(role: .destructive) {
											if accessoryManager.allowDisconnect {
												Task {
													try await accessoryManager.disconnect()
												}
											}
										} label: {
											Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
										}
										Button(role: .destructive) {
											// Re-check liveness at tap time: the menu-captured `node` can fault if
											// the context is recreated between the menu appearing and this tap, and
											// reading `.num` on a faulted @Model would trap (the #2006 crash class).
											pendingShutdownNodeNum = Connect.liveNode(node)?.num
											showingShutdownConfirm = true
										} label: {
											Label("Power Off", systemImage: "power")
										}
									}
								}
							}
							if isUnsetRegion {
								HStack {
									NavigationLink {
										LoRaConfig(node: safeNode)
									} label: {
										Label("Set LoRa Region", systemImage: "globe.americas.fill")
											.foregroundColor(.red)
											.font(.title)
									}
								}
							}
						} else {
							if accessoryManager.isConnecting {
								HStack {
									Image(systemName: "antenna.radiowaves.left.and.right")
										.resizable()
										.symbolRenderingMode(.hierarchical)
										.foregroundColor(.orange)
										.frame(width: 60, height: 60)
										.padding(.trailing)
									switch accessoryManager.state {
									case .connecting, .communicating:
										Text("Connecting . .")
											.font(.title2)
											.foregroundColor(.orange)
									case .retrievingDatabase:
										Text("Retreiving nodes . .")
											.font(.callout)
											.foregroundColor(.orange)
									case .retrying(let attempt, let maxAttempts):
										Text("Connection Attempt \(attempt) of \(maxAttempts)")
											.font(.callout)
											.foregroundColor(.orange)
									default:
										EmptyView()
									}
								}
								.padding()
								.swipeActions {
									if accessoryManager.allowDisconnect {
										Button(role: .destructive) {
											Task {
												try await accessoryManager.disconnect()
											}
										} label: {
											Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
										}
										.disabled(!accessoryManager.allowDisconnect)
									}
								}
								
							} else {
								
								if let lastError = accessoryManager.lastConnectionError as? Error {
									Text(lastError.localizedDescription).font(.callout).foregroundColor(.red)
								}
								HStack {
									Image("custom.link.slash")
										.resizable()
										.symbolRenderingMode(.hierarchical)
										.foregroundColor(.red)
										.frame(width: 60, height: 60)
										.padding(.trailing)
									Text("No device connected").font(.title3)
								}
								.padding()
							}
						}
					}
					.textCase(nil)
					
					if !(accessoryManager.isConnected || accessoryManager .isConnecting) {
						Group {
							Section(header: HStack {
								Text("Available Radios").font(.title)
								Spacer()
								ManualConnectionMenu(isSwitchingRadio: $isSwitchingRadio)
							}) {
									ForEach(sortedAvailableDevices) { device in
										DeviceConnectRow(device: device, isSwitchingRadio: $isSwitchingRadio)
								}
							}
						if manualConnections.connectionsList.count > 0 {
							Section(header: Text("Manual Connections").font(.title)) {
								ForEach(manualConnections.connectionsList) { device in
										DeviceConnectRow(device: device, isSwitchingRadio: $isSwitchingRadio)
#if targetEnvironment(macCatalyst)
										.contextMenu {
											Button {
												manualConnections.remove(device: device)
											} label: {
												Label("Delete", systemImage: "trash")
											}
										}
#endif
								}.onDelete { offsets in
									manualConnections.remove(atOffsets: offsets)
								}

							}
						}

						// ── Wi-Fi Provisioning (mPWRD-OS / nymea-networkmanager) ──
						// Devices broadcasting nymea-networkmanager service are picked
						// up by the passive scan started in .onAppear below.
						if !nymeaProvisioning.discoverable.isEmpty {
							Section(header: Text("Wi-Fi Setup").font(.title)) {
								ForEach(nymeaProvisioning.discoverable) { device in
								NymeaDeviceConnectRow(device: device) {
									pendingNymeaDevice = device
								}
								}
							}
						}
						}
						.textCase(nil)
					}
				}
				.scrollContentBackground(.hidden)
				HStack(alignment: .center) {
					Spacer()
#if targetEnvironment(macCatalyst)
					// TODO: should this be allowDisconnect?
					if accessoryManager.allowDisconnect {
						Button(role: .destructive, action: {
							if accessoryManager.allowDisconnect {
								Task {
									try await accessoryManager.disconnect()
								}
							}
						}) {
							Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding()
					}
#endif
					Spacer()
				}
				.padding(.bottom, 10)
			}
			.background(Color(.systemGroupedBackground))
			.disabled(isSwitchingRadio)
			.overlay {
				if isSwitchingRadio {
					ZStack {
						Color.black.opacity(0.2)
							.ignoresSafeArea()

						VStack(spacing: 14) {
							ProgressView()
								.controlSize(.large)
							Text("Switching Radio")
								.font(.headline)
						}
						.padding(.horizontal, 28)
						.padding(.vertical, 22)
						.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
					}
				}
			}
			.navigationTitle("Connect")
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					MeshtasticLogo()
				}
				ToolbarItem(placement: .topBarTrailing) {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?",
						mqttProxyConnected: accessoryManager.mqttProxyConnected,
						mqttTopic: accessoryManager.mqttManager.topics.first ?? ""
					)
				}
			}
			// Attached to the root VStack (not the connected-device subtree, which unmounts
			// on disconnect) so the confirmation survives a connection state change between
			// the long-press and the user tapping "Shutdown Node?".
			.confirmationDialog(
				"Are you sure?",
				isPresented: $showingShutdownConfirm,
				titleVisibility: .visible
			) {
				Button("Shutdown Node?", role: .destructive) {
					Task {
						// Resolve the target at confirm time rather than capturing it ahead of the
						// dialog: a cached @Model can fault if the context is recreated (disconnect/
						// reconnect, node switch) while the dialog is up, and reading a faulted model
						// traps. shutdownTarget gates on modelContext != nil and verifies the live
						// node still matches the identity captured when the menu was opened, so the
						// shutdown can't drift to a node connected after the long-press.
						guard let user = Connect.shutdownTarget(for: node, expectedNum: pendingShutdownNodeNum) else {
							Logger.mesh.warning("Shutdown skipped: no live connected node or connection changed")
							return
						}
						do {
							try await accessoryManager.sendShutdown(fromUser: user, toUser: user)
						} catch {
							Logger.mesh.error("Shutdown Failed: \(error)")
						}
					}
				}
			}
		}
		// TODO: REMOVING VERSION STUFF?
		//		.sheet(isPresented: $invalidFirmwareVersion, onDismiss: didDismissSheet) {
		//			InvalidVersion(minimumVersion: accessoryManager.minimumVersion, version: accessoryManager.activeConnection?.device.firmwareVersion ?? "?.?.?")
		//				.presentationDetents([.large])
		//				.presentationDragIndicator(.automatic)
		//		}
		//		.onChange(of: accessoryManager) {
		//			invalidFirmwareVersion = self.bleManager.invalidVersion
		//		}
		.sheet(isPresented: $invalidFirmwareVersion) {
			InvalidVersion(minimumVersion: accessoryManager.minimumVersion, version: accessoryManager.activeConnection?.device.firmwareVersion ?? "?.?.?")
				.presentationDetents([.large])
				.presentationDragIndicator(.automatic)
		}
		.sheet(isPresented: $showSecurityVersionNag) {
			SecurityVersionNag(minimumSecureVersion: accessoryManager.securityVersion, version: accessoryManager.activeConnection?.device.firmwareVersion ?? "?.?.?")
				.presentationDetents([.large])
				.presentationDragIndicator(.automatic)
		}
		.onChange(of: self.accessoryManager.state) { _, state in
			// Clear stale node data when not subscribed to prevent showing previous connection's info
			if state != .subscribed {
				node = nil
			}
			
			if let deviceNum = accessoryManager.activeDeviceNum, UserDefaults.preferredPeripheralId.count > 0 && state == .subscribed {
				
				var fetchNodeInfoRequest = FetchDescriptor<NodeInfoEntity>(
					predicate: #Predicate<NodeInfoEntity> { $0.num == deviceNum }
				)
				fetchNodeInfoRequest.fetchLimit = 1
				
				do {
					node = try context.fetch(fetchNodeInfoRequest).first
					if let loRaConfig = node?.loRaConfig, loRaConfig.regionCode == RegionCodes.unset.rawValue {
						isUnsetRegion = true
					} else {
						isUnsetRegion = false
					}
				} catch {
					Logger.data.error("💥 Error fetching node info: \(error.localizedDescription, privacy: .public)")
				}
			// Check firmware version on connection (only if version is known)
			if let firmwareVersion = accessoryManager.activeConnection?.device.firmwareVersion, firmwareVersion != "?.?.?" && !firmwareVersion.isEmpty {
				let meetsMinimumVersion = accessoryManager.checkIsVersionSupported(forVersion: accessoryManager.minimumVersion)
				let meetsSecurityVersion = accessoryManager.checkIsVersionSupported(forVersion: accessoryManager.securityVersion)
				invalidFirmwareVersion = !meetsMinimumVersion
				showSecurityVersionNag = meetsMinimumVersion && !meetsSecurityVersion
			}
			}
		}
		.sheet(item: $pendingNymeaDevice, onDismiss: {
			updateNymeaDiscovery()
		}) { device in
			WifiProvisioningView(preselectedDevice: device)
		}
		.onAppear { updateNymeaDiscovery() }
		.onDisappear { nymeaProvisioning.stopDiscovery() }
		.onChange(of: scenePhase) { _, _ in updateNymeaDiscovery() }
		.onChange(of: accessoryManager.isConnected) { _, _ in updateNymeaDiscovery() }
		.onChange(of: accessoryManager.isConnecting) { _, _ in updateNymeaDiscovery() }
		.task(id: safeNode?.num) {
			// Refresh the connected node's battery on an interval instead of fetching in
			// `body` (which re-ran the TelemetryEntity query on every render — costly while
			// ingestion churns the node @Query). Battery changes slowly, so 15s is plenty.
			while !Task.isCancelled {
				connectedBatteryLevel = latestBatteryLevel(for: node)
				try? await Task.sleep(for: .seconds(15))
			}
		}
	}

	/// Fetch only the latest device metrics battery level without faulting all telemetries.
	private func latestBatteryLevel(for node: NodeInfoEntity?) -> Int32? {
		guard let nodeNum = node?.num else { return nil }
		let metricsType: Int32 = 0
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		guard let result = try? context.fetch(descriptor).first else { return nil }
		let level = result.batteryLevel ?? 0
		return level > 0 ? level : nil
	}

	/// Starts nymea passive discovery only when the Connect view is foreground-visible
	/// and the app has no primary transport in flight; otherwise stops it.
	private func updateNymeaDiscovery() {
		let canScan = scenePhase == .active
			&& !accessoryManager.isConnected
			&& !accessoryManager.isConnecting
			&& pendingNymeaDevice == nil
			&& !UserDefaults.firstLaunch
		if canScan {
			nymeaProvisioning.startDiscovery()
		} else {
			nymeaProvisioning.stopDiscovery()
		}
	}
#if !targetEnvironment(macCatalyst)
#if canImport(ActivityKit)
	func startNodeActivity() {
		liveActivityStarted = true
		// 15 Minutes Local Stats Interval
		let timerSeconds = 900
		let nodeNum = node?.num ?? 0
		let metricsType: Int32 = 4
		var statsDescriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		statsDescriptor.fetchLimit = 1
		let mostRecent = try? context.fetch(statsDescriptor).first
		
		let activityAttributes = MeshActivityAttributes(nodeNum: Int(node?.num ?? 0), name: node?.user?.longName?.addingVariationSelectors ?? "unknown", shortName: node?.user?.shortName ?? "?")
		
		let future = Date(timeIntervalSinceNow: Double(timerSeconds))
		let initialContentState = MeshActivityAttributes.ContentState(uptimeSeconds: UInt32(bitPattern: mostRecent?.uptimeSeconds ?? 0),
																	  channelUtilization: mostRecent?.channelUtilization ?? 0.0,
																	  airtime: mostRecent?.airUtilTx ?? 0.0,
																	  sentPackets: UInt32(bitPattern: mostRecent?.numPacketsTx ?? 0),
																	  receivedPackets: UInt32(bitPattern: mostRecent?.numPacketsRx ?? 0),
																	  badReceivedPackets: UInt32(bitPattern: mostRecent?.numPacketsRxBad ?? 0),
																	  dupeReceivedPackets: UInt32(bitPattern: mostRecent?.numRxDupe ?? 0),
																	  packetsSentRelay: UInt32(bitPattern: mostRecent?.numTxRelay ?? 0),
																	  packetsCanceledRelay: UInt32(bitPattern: mostRecent?.numTxRelayCanceled ?? 0),
																	  nodesOnline: UInt32(bitPattern: mostRecent?.numOnlineNodes ?? 0),
																	  totalNodes: UInt32(bitPattern: mostRecent?.numTotalNodes ?? 0),
																	  timerRange: Date.now...future)
		
		let activityContent = ActivityContent(state: initialContentState, staleDate: Calendar.current.date(byAdding: .minute, value: 15, to: Date())!)
		
		do {
			let myActivity = try Activity<MeshActivityAttributes>.request(attributes: activityAttributes, content: activityContent,
																		  pushType: nil)
			Logger.services.info("Requested MyActivity live activity. ID: \(myActivity.id)")
		} catch {
			Logger.services.error("Error requesting live activity: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	func endActivity() {
		liveActivityStarted = false
		Task {
			for activity in Activity<MeshActivityAttributes>.activities where activity.attributes.nodeNum == node?.num ?? 0 {
				await activity.end(nil, dismissalPolicy: .immediate)
			}
		}
	}
#endif
#endif
	func didDismissSheet() {
		// bleManager.disconnectPeripheral(reconnect: false)
		Task {
			try await accessoryManager.disconnect()
		}
	}
}

struct TransportIcon: View {
	var transportType: TransportType
	@EnvironmentObject var accessoryManager: AccessoryManager
	
	var body: some View {
		let transport = accessoryManager.transportForType(transportType)
		return HStack(spacing: 3.0) {
			if let icon = transport?.type.icon {
				icon
					.font(.title2)
					.foregroundColor(transport?.type == .ble ? Color.accentColor : Color.primary)
			} else {
				Image(systemName: "questionmark")
					.font(.title2)
			}
			Text(transport?.type.rawValue ?? "Unknown".localized)
				.font(.title3)
		}
	}
}

struct ManualConnectionMenu: View {

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Binding var isSwitchingRadio: Bool

	private struct IterableTransport: Identifiable {
		let id: UUID
		let icon: Image
		let title: String
		let transport: any Transport
	}
	
	private var transports: [IterableTransport]
	
	init(isSwitchingRadio: Binding<Bool>) {
		self._isSwitchingRadio = isSwitchingRadio
		self.transports = AccessoryManager.shared.transports.filter { $0.supportsManualConnection }.map { transport in
			IterableTransport(id: UUID(), icon: transport.type.icon, title: transport.type.rawValue, transport: transport)
		}
	}
	
	@State private var selectedTransport: IterableTransport?
	@State private var showAlert: Bool = false
	@State private var connectionString = ""

	var body: some View {
		Menu {
			ForEach(transports) { transport in
				Button {
					self.selectedTransport = transport
					self.showAlert = true
				} label: {
					Label(title: { Text(transport.title)}, icon: { transport.icon })
				}
			}
		} label: {
			Label("Manual", systemImage: "plus")
		}.alert("Manual connection string", isPresented: $showAlert, presenting: selectedTransport) { selectedTransport in
			// This continues to be quick and dirty. A better system is needed.
			TextField("Enter hostname[:port]", text: $connectionString)
				.keyboardType(.URL)
				.autocapitalization(.none)
				.disableAutocorrection(true)
				.onChange(of: connectionString) { _, newValue in
					// Filter to only allow valid characters for hostname/IP:port
					let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
					let filtered = String(newValue.unicodeScalars.filter { allowedCharacters.contains($0) })
					if filtered != newValue {
						connectionString = filtered
					}
				}
			
			Button("OK", action: {
				if !connectionString.isEmpty {
					if let device = selectedTransport.transport.device(forManualConnection: connectionString) {
						if UserDefaults.preferredPeripheralId == device.id.uuidString {
							Task {
								try await selectedTransport.transport.manuallyConnect(toDevice: device)
							}
						} else {
							Task {
								await performRadioSwitch(device, isSwitchingRadio: $isSwitchingRadio, accessoryManager: accessoryManager)
							}
						}
					}
				}
			})
		}
	}
}

struct DeviceConnectRow: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	let device: Device
	@Binding var isSwitchingRadio: Bool
	
	var body: some View {
		HStack {
			if UserDefaults.preferredPeripheralId == device.id.uuidString {
				Image(systemName: "star.fill")
					.imageScale(.large).foregroundColor(.yellow)
					.padding(.trailing)
			} else {
				Image(systemName: "circle.fill")
					.imageScale(.large).foregroundColor(.gray)
					.padding(.trailing)
			}
			VStack(alignment: .leading) {
				Button(action: {
					if UserDefaults.preferredPeripheralId.count > 0 && device.id.uuidString != UserDefaults.preferredPeripheralId {
						Task {
							await performRadioSwitch(device, isSwitchingRadio: $isSwitchingRadio, accessoryManager: accessoryManager)
						}
					} else {
						Task {
							try? await accessoryManager.connect(to: device)
						}
					}
				}) {
					Text(device.name).font(.callout)
				}
				// Show transport type
#if !targetEnvironment(macCatalyst)
				HStack(alignment: .center) {
					TransportIcon(transportType: device.transportType)
					if device.isManualConnection && (device.longName != nil || device.shortName != nil) {
						VStack(alignment: .leading) {
							Text("Last seen device:")
							Text("\(String(describing: device))")
						}
					}
				}.padding(.top, 3.0)
#else
				// Different alignment for Mac
				HStack(alignment: .firstTextBaseline) {
					TransportIcon(transportType: device.transportType)
					if device.isManualConnection && (device.longName != nil || device.shortName != nil) {
						Text("Last seen device: \(String(describing: device))")
					}
				}
#endif
			}
			Spacer()
			VStack {
				device.getSignalStrength().map {
					SignalStrengthIndicator(signalStrength: $0)
				}
			}
		}.padding([.bottom, .top])
	}
}

@MainActor
func performRadioSwitch(_ device: Device, isSwitchingRadio: Binding<Bool>, accessoryManager: AccessoryManager) async {
	isSwitchingRadio.wrappedValue = true

	await switchToDevice(
		device,
		accessoryManager: accessoryManager,
		appState: accessoryManager.appState,
		onRestoreComplete: {
			isSwitchingRadio.wrappedValue = false
		}
	)
}

@MainActor
func backupCurrentDatabase(forTargetNode targetNodeNum: Int64?, accessoryManager: AccessoryManager) async {
	let currentNodeNum = accessoryManager.activeDeviceNum ?? {
		let num = Int64(UserDefaults.preferredPeripheralNum)
		return num > 0 ? num : nil
	}()
	let currentNodeName = currentNodeNum.flatMap { num in
		accessoryManager.devices.first(where: { $0.num == num })?.longName
	}

	await MeshPackets.shared.flushDebouncedSaves()
	try? accessoryManager.context.save()

	if let currentNodeNum, currentNodeNum != targetNodeNum {
		Logger.backup.info("💾 Creating backup for current node \(currentNodeNum) before restore")
		let backupResult = await NodeBackupManager.shared.createBackup(
			forNode: currentNodeNum,
			nodeName: currentNodeName
		)
		switch backupResult {
		case .success(let entry):
			Logger.backup.info("💾 Backup created: \(entry.fileSize) bytes for node \(currentNodeNum)")
		case .skipped(let reason):
			Logger.backup.warning("💾 Backup skipped: \(reason, privacy: .public)")
		case .noBackupFound:
			break
		}
	} else if currentNodeNum == targetNodeNum {
		Logger.backup.info("💾 Skipping current backup because target backup is for the active node")
	} else {
		Logger.backup.warning("💾 No current node num — skipping backup")
	}
}

@MainActor
func backupCurrentAndRestoreDatabase(
	forNode targetNodeNum: Int64,
	accessoryManager: AccessoryManager,
	appState: AppState,
	selectedTab: NavigationState.Tab,
	disconnectCurrentDevice: Bool = false
) async -> NodeBackupResult {
	await backupCurrentDatabase(forTargetNode: targetNodeNum, accessoryManager: accessoryManager)

	if disconnectCurrentDevice, accessoryManager.allowDisconnect {
		Logger.backup.info("💾 Disconnecting current device before restore")
		try? await accessoryManager.disconnect()
	}

	appState.router.popToRoot(tab: .messages)
	appState.router.popToRoot(tab: .nodes)
	appState.router.popToRoot(tab: .map)
	appState.router.popToRoot(tab: .settings)
	appState.router.selectedTab = selectedTab
	await Task.yield()

	await MeshPackets.shared.flushDebouncedSaves()
	await MeshPackets.shared.clearDatabase(includeRoutes: false)
	// Repoint at a fresh container so the restore below (and the post-restore UI refresh) operate
	// on a context with no stale registrations. The databaseResetID bump stays after the restore.
	accessoryManager.repointToFreshContainer()
	Logger.backup.info("💾 Database cleared and container recreated")

	let restoreResult = await NodeBackupManager.shared.restoreFromBackup(
		forNode: targetNodeNum,
		into: PersistenceController.shared.container
	)

	// The clear ran on the MeshPackets context and the restore imported through a separate
	// liveContext, neither of which the UI's main context observes — and a batch delete sends
	// no change notification, so the existing @Query views keep their previously-fetched
	// results (the previous node's nodes/pins linger; e.g. switching back to a local node
	// still shows the other node's map pins). Bumping databaseResetID re-identifies the root
	// view, forcing every @Query to re-execute its fetch and return only the restored data.
	appState.databaseResetID = UUID()

	return restoreResult
}

// MARK: - Node Switch Helper

/// Handles the full node-switch lifecycle: backup, clear, restore, connect.
///
/// Flow:
/// 1. Capture current node number
/// 2. Flush pending writes
/// 3. Create backup of current node's database (full SQLite file copy)
/// 4. Disconnect from current device
/// 5. Clear database via MeshPackets actor (empties @Query results safely)
/// 6. Swap database files and recreate ModelContainer (full restore)
/// 7. Trigger UI reset so views rebind to the new container
/// 8. Connect to new device (radio sends updates on top of restored data)
@MainActor
func switchToDevice(
	_ device: Device,
	accessoryManager: AccessoryManager,
	appState: AppState,
	onRestoreComplete: (@MainActor () -> Void)? = nil
) async {
	let resolvedTargetNodeNum = await NodeBackupManager.shared.resolveNodeNum(forPeripheralId: device.id.uuidString)
	let targetNodeNum = device.num ?? resolvedTargetNodeNum
	let currentNodeNum = accessoryManager.activeDeviceNum ?? {
		let num = Int64(UserDefaults.preferredPeripheralNum)
		return num > 0 ? num : nil
	}()
	Logger.backup.info("💾 Node switch — current: \(currentNodeNum.map { String($0) } ?? "nil", privacy: .public), target: \(targetNodeNum.map { String($0) } ?? "unknown", privacy: .public)")

	// 4. Disconnect from current device
	if accessoryManager.allowDisconnect {
		try? await accessoryManager.disconnect()
	}

	await backupCurrentDatabase(forTargetNode: targetNodeNum, accessoryManager: accessoryManager)

	if let targetNodeNum {
		let restoreResult = await backupCurrentAndRestoreDatabase(
			forNode: targetNodeNum,
			accessoryManager: accessoryManager,
			appState: appState,
			selectedTab: .connect
		)
		switch restoreResult {
		case .success:
			Logger.backup.info("💾 Backup restored for target node \(targetNodeNum)")
		case .skipped(let reason):
			Logger.backup.warning("💾 Restore skipped: \(reason, privacy: .public)")
		case .noBackupFound:
			Logger.backup.info("💾 No backup for target node \(targetNodeNum) — radio will populate fresh data")
		}
	} else {
		Logger.backup.warning("💾 Target node num is nil — cannot restore, radio will populate fresh data")
	}

	onRestoreComplete?()

	// 8. Clear notifications and connect to new device
	clearNotifications()
	do {
		try await accessoryManager.connect(to: device, refreshDeviceHardwareFromAPI: true)
		Logger.backup.info("💾 Connected to target device successfully")
	} catch {
		Logger.backup.error("💾 Failed to connect to target: \(error.localizedDescription, privacy: .public)")
	}
}

// MARK: - Nymea (mPWRD-OS) discovery row

/// A row representing a discovered nymea-networkmanager device that needs Wi-Fi
/// provisioning. Tapping it begins the provisioning workflow targeted at the device.
struct NymeaDeviceConnectRow: View {
	let device: NymeaDiscoveredDevice
	let onSelect: () -> Void

	var body: some View {
		HStack {
			Image(systemName: "circle.fill")
				.foregroundColor(.gray)
			VStack(alignment: .leading) {
				Text(device.name).font(.callout)
				HStack(alignment: .center) {
					Image(systemName: "wifi.router")
						.foregroundColor(.accentColor)
					Text("Wi-Fi Setup")
						.font(.caption)
						.foregroundColor(.secondary)
				}.padding(.top, 3.0)
			}
			Spacer()
			SignalStrengthIndicator(signalStrength: rssiToSignalStrength(device.rssi))
		}
		.padding([.bottom, .top])
		.contentShape(Rectangle())
		.onTapGesture { onSelect() }
	}

	private func rssiToSignalStrength(_ rssi: Int) -> BLESignalStrength {
		switch rssi {
		case ..<(-80): return .weak
		case -80 ..< -65: return .normal
		default: return .strong
		}
	}
}
