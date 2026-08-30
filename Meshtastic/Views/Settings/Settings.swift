//
//  Settings.swift
//  MeshtasticApple
//
//  Copyright (c) Garth Vander Houwen 6/9/22.
//

import SwiftUI
import SwiftData
import OSLog
import TipKit
import MeshtasticProtobufs

enum RemoteAdminWording {
	struct ActivePresentation: Equatable {
		let format: String
		let systemImage: String
		let representsVerifiedSignature: Bool
	}

	static func activePresentation(localOwnerIsLicensed: Bool) -> ActivePresentation {
		localOwnerIsLicensed
			? ActivePresentation(format: "Remote Signed Admin: %@", systemImage: "checkmark.shield", representsVerifiedSignature: true)
			: ActivePresentation(format: "Remote PKI Admin: %@", systemImage: "av.remote", representsVerifiedSignature: false)
	}

	static func requestFormat(localOwnerIsLicensed: Bool) -> String {
		localOwnerIsLicensed ? "Request Signed Admin: %@" : "Request PKI Admin: %@"
	}
}

// MARK: - SettingsNodeSnapshot

/// Settings data captured while the corresponding node is still live.
///
/// Settings retains its node list between periodic fetches. Keeping only value data here stops
/// `body` from reading a node or relationship invalidated by a store reset.
struct SettingsNodeSnapshot: Identifiable, Equatable {
	let num: Int64
	let favorite: Bool
	let canRemoteAdmin: Bool
	let hasSessionPasskey: Bool
	let hasMetadata: Bool
	let hasTAKConfig: Bool
	let userLongName: String?
	let userIsLicensed: Bool
	let userIsPkiEncrypted: Bool
	let role: Int32?
	let regionCode: Int?
	let excludedModules: Int
	let isManaged: Bool

	var id: Int64 { num }

	@MainActor init?(node: NodeInfoEntity) {
		guard node.modelContext != nil, !node.isDeleted else { return nil }

		num = node.num
		favorite = node.favorite
		canRemoteAdmin = node.canRemoteAdmin
		hasSessionPasskey = node.sessionPasskey != nil

		if let user = node.user,
			user.modelContext != nil,
			!user.isDeleted {
			userLongName = user.longName
			userIsLicensed = user.isLicensed
			userIsPkiEncrypted = user.pkiEncrypted
			let userRole = user.role
			if let deviceConfig = node.deviceConfig,
				deviceConfig.modelContext != nil,
				!deviceConfig.isDeleted {
				isManaged = deviceConfig.isManaged
				role = deviceConfig.role
			} else {
				isManaged = false
				role = userRole
			}
		} else {
			userLongName = nil
			userIsLicensed = false
			userIsPkiEncrypted = false
			if let deviceConfig = node.deviceConfig,
				deviceConfig.modelContext != nil,
				!deviceConfig.isDeleted {
				isManaged = deviceConfig.isManaged
				role = deviceConfig.role
			} else {
				isManaged = false
				role = nil
			}
		}

		if let loRaConfig = node.loRaConfig,
			loRaConfig.modelContext != nil,
			!loRaConfig.isDeleted {
			regionCode = Int(loRaConfig.regionCode)
		} else {
			regionCode = nil
		}

		if let metadata = node.metadata,
			metadata.modelContext != nil,
			!metadata.isDeleted {
			hasMetadata = true
			excludedModules = Int(metadata.excludedModules)
		} else {
			hasMetadata = false
			excludedModules = 0
		}

		if let takConfig = node.takConfig,
			takConfig.modelContext != nil,
			!takConfig.isDeleted {
			hasTAKConfig = true
		} else {
			hasTAKConfig = false
		}
	}
}

struct Settings: View {
	@Environment(\.modelContext) private var context
	@Environment(\.colorScheme) private var colorScheme
	@EnvironmentObject var accessoryManager: AccessoryManager
	/// Node snapshots for the admin picker / config gating, refreshed on a throttled cadence (see the
	/// `.task` in `body`) instead of a live `@Query`. A live query re-evaluated this whole view's
	/// `body` on every node write — and TabView keeps Settings alive on other tabs, so under heavy
	/// ingestion (large mesh, TCP replay) it burned main-thread CPU while completely off-screen.
	@State private var nodes: [SettingsNodeSnapshot] = []

	private func refreshNodes() {
		let descriptor = FetchDescriptor<NodeInfoEntity>(sortBy: [SortDescriptor(\NodeInfoEntity.lastHeard, order: .reverse)])
		nodes = ((try? context.fetch(descriptor)) ?? []).compactMap(SettingsNodeSnapshot.init)
	}

	/// Nodes for the admin / configuration picker, ordered favorites-first while
	/// preserving the snapshot fetch's `lastHeard`-descending order within each group. The
	/// favorite-on-top behavior can't be expressed as a SwiftData `@Query` sort
	/// because `favorite` is a `Bool` and `Bool` isn't `Comparable` (so it's not a
	/// valid `SortDescriptor` key); it's applied here as a cheap stable partition over value data.
	private var sortedNodes: [SettingsNodeSnapshot] {
		nodes.filter(\.favorite) + nodes.filter { !$0.favorite }
	}

	private func nodeSnapshot(for nodeNum: Int) -> SettingsNodeSnapshot? {
		sortedNodes.first(where: { $0.num == Int64(nodeNum) })
	}

	private func liveNode(for nodeNum: Int) -> NodeInfoEntity? {
		guard nodeNum > 0,
			let node = getNodeInfo(id: Int64(nodeNum), context: context),
			node.modelContext != nil,
			!node.isDeleted
		else { return nil }
		return node
	}

	private var localOwnerIsLicensed: Bool {
		guard let activeDeviceNum = accessoryManager.activeDeviceNum else { return false }
		return nodes.first(where: { $0.num == activeDeviceNum })?.userIsLicensed == true
	}

	@State private var selectedNode: Int = 0
	@State private var preferredNodeNum: Int = 0

	@EnvironmentObject
	var router: Router

	// MARK: Helper

	private var moduleConfigurationNode: SettingsNodeSnapshot? {
		let nodeNum = selectedNode > 0 ? selectedNode : preferredNodeNum
		return nodeSnapshot(for: nodeNum)
	}

	// The module-support helpers take a pre-resolved node snapshot + excluded-modules bitmask so
	// `moduleConfigurationSection` can compute them ONCE per render. They used to read the
	// `moduleConfigurationNode` computed property (a linear scan over the full node snapshot
	// plus a `.metadata` relationship fault) on every call, and the section calls them ~28×
	// per render — which, under live ingestion re-rendering, pegged the main thread.
	private func showsAnyModuleConfiguration(node: SettingsNodeSnapshot?, excludedModules: Int) -> Bool {
		isAnySupported([
			.ambientlightingConfig,
			.audioConfig,
			.cannedmsgConfig,
			.detectionsensorConfig,
			.extnotifConfig,
			.mqttConfig,
			.neighborinfoConfig,
			.rangetestConfig,
			.paxcounterConfig,
			.serialConfig,
			.storeforwardConfig,
			.telemetryConfig
		], excludedModules: excludedModules)
			|| isTAKModuleSupported(node)
			|| isTrafficManagementModuleSupported(node)
			|| isMeshBeaconModuleSupported(node)
	}

	private func isMeshBeaconModuleSupported(_ node: SettingsNodeSnapshot?) -> Bool {
		guard node != nil else { return false }
		return accessoryManager.checkIsVersionSupported(forVersion: "2.8.0")
	}

	private func isModuleSupported(_ module: ExcludedModules, excludedModules: Int) -> Bool {
		return excludedModules & module.rawValue == 0
	}

	private func isAnySupported(_ modules: [ExcludedModules], excludedModules: Int) -> Bool {
		return modules.contains { isModuleSupported($0, excludedModules: excludedModules) }
	}

	private func isTAKModuleSupported(_ node: SettingsNodeSnapshot?) -> Bool {
		guard let node else { return false }
		if node.hasTAKConfig {
			return true
		}

		guard let roleValue = node.role,
			  let deviceRole = DeviceRoles(rawValue: Int(roleValue)) else {
			return false
		}

		return deviceRole == .tak || deviceRole == .takTracker
	}

	private func isTrafficManagementModuleSupported(_ node: SettingsNodeSnapshot?) -> Bool {
		guard node != nil else { return false }
		return accessoryManager.checkIsVersionSupported(forVersion: "2.8.0")
	}

	private var showsDevelopersSection: Bool {
		Bundle.main.isDebug || Bundle.main.isTestFlight
	}

	// MARK: Views

	var radioConfigurationSection: some View {
		Section("Radio Configuration") {
			let node = nodeSnapshot(for: preferredNodeNum)
			if let node,
				let regionCode = node.regionCode,
				let rc = RegionCodes(rawValue: regionCode),
				!node.userIsLicensed,
				rc.dutyCycle > 0 && rc.dutyCycle < 100 {
				Label {
					Text("Hourly Duty Cycle")
				} icon: {
					Image(systemName: "clock.arrow.circlepath")
						.symbolRenderingMode(.hierarchical)
						.foregroundColor(.red)
				}
				Text("Your region has a \(rc.dutyCycle)% hourly duty cycle, your radio will stop sending packets when it reaches the hourly limit.")
					.foregroundColor(.orange)
					.font(.caption)
				Text("Limit all periodic broadcast intervals especially telemetry and position. If you need to increase hops, do it on nodes at the edges, not the ones in the middle. MQTT is not advised when you are duty cycle restricted because the gateway node is then doing all the work.")
					.font(.caption2)
					.foregroundColor(.gray)
			}

			NavigationLink(value: SettingsNavigationState.lora) {
				Label {
					Text("LoRa")
				} icon: {
					Image(systemName: "dot.radiowaves.left.and.right")
						.rotationEffect(.degrees(-90))
				}
			}

			NavigationLink(value: SettingsNavigationState.channels) {
				Label {
					Text("Channels")
				} icon: {
					Image(systemName: "fibrechannel")
				}
			}
			.disabled(selectedNode > 0 && selectedNode != preferredNodeNum)

			NavigationLink(value: SettingsNavigationState.security) {
				Label {
					Text("Security")
				} icon: {
					Image(systemName: "lock.shield")
				}
			}

			NavigationLink(value: SettingsNavigationState.shareQRCode) {
				Label {
					Text("Share QR Code")
				} icon: {
					Image(systemName: "qrcode")
				}
			}
			.disabled(selectedNode > 0 && selectedNode != preferredNodeNum)
		}
	}

	var deviceConfigurationSection: some View {
		Section("Device Configuration") {
			NavigationLink(value: SettingsNavigationState.user) {
				Label {
					Text("User")
				} icon: {
					Image(systemName: "person.crop.rectangle.fill")
				}
			}

			NavigationLink(value: SettingsNavigationState.bluetooth) {
				Label {
					Text("Bluetooth")
				} icon: {
					Image(systemName: "antenna.radiowaves.left.and.right")
				}
			}

			NavigationLink(value: SettingsNavigationState.device) {
				Label {
					Text("Device")
				} icon: {
					Image(systemName: "flipphone")
				}
			}

			NavigationLink(value: SettingsNavigationState.display) {
				Label {
					Text("Display")
				} icon: {
					Image(systemName: "display")
				}
			}

			NavigationLink(value: SettingsNavigationState.network) {
				Label {
					Text("Network")
				} icon: {
					Image(systemName: "network")
				}
			}

			NavigationLink(value: SettingsNavigationState.position) {
				Label {
					Text("Position")
				} icon: {
					Image(systemName: "location")
				}
			}

			NavigationLink(value: SettingsNavigationState.power) {
				Label {
					Text("Power")
				} icon: {
					Image(systemName: "bolt.fill")
				}
			}
		}
	}

	var moduleConfigurationSection: some View {
		// Resolve the target node and its excluded-modules bitmask ONCE per render, then feed
		// them to the cheap per-module checks below (formerly each re-scanned the node @Query
		// and re-faulted metadata — ~28× per render).
		let node = moduleConfigurationNode
		let excludedModules = node?.excludedModules ?? 0
		return Section {
			if isModuleSupported(.ambientlightingConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.ambientLighting) {
					Label {
						Text("Ambient Lighting")
					} icon: {
						Image(systemName: "light.max")
					}
				}
			}

			if isModuleSupported(.audioConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.audio) {
					Label {
						Text("Audio")
					} icon: {
						Image(systemName: "waveform")
					}
				}
			}

			if isModuleSupported(.cannedmsgConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.cannedMessages) {
					Label {
						Text("Canned Messages")
					} icon: {
						Image(systemName: "list.bullet.rectangle.fill")
					}
				}
			}

			if isModuleSupported(.detectionsensorConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.detectionSensor) {
					Label {
						Text("Detection Sensor")
					} icon: {
						Image(systemName: "sensor")
					}
				}
			}

			if isMeshBeaconModuleSupported(node) {
				NavigationLink(value: SettingsNavigationState.meshBeacon) {
					Label {
						Text("Mesh Beacon")
					} icon: {
						Image(systemName: "dot.radiowaves.left.and.right")
					}
				}
			}

			if isModuleSupported(.extnotifConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.externalNotification) {
					Label {
						Text("External Notification")
					} icon: {
						Image(systemName: "megaphone")
					}
				}
			}

			if isModuleSupported(.mqttConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.mqtt) {
					Label {
						Text("MQTT")
					} icon: {
						Image(systemName: "dot.radiowaves.up.forward")
					}
				}
			}

			if isModuleSupported(.neighborinfoConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.neighborInfo) {
					Label {
						Text("Neighbor Info")
					} icon: {
						Image(systemName: "network")
					}
				}
			}

			if isModuleSupported(.rangetestConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.rangeTest) {
					Label {
						Text("Range Test")
					} icon: {
						Image(systemName: "point.3.connected.trianglepath.dotted")
					}
				}
			}

			if isModuleSupported(.paxcounterConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.paxCounter) {
					Label {
						Text("PAX Counter")
					} icon: {
						Image(systemName: "figure.walk.motion")
					}
				}
			}

			if isModuleSupported(.extnotifConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.ringtone) {
					Label {
						Text("Ringtone")
					} icon: {
						Image(systemName: "music.note.list")
					}
				}
			}

			if isModuleSupported(.serialConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.serial) {
					Label {
						Text("Serial")
					} icon: {
						Image(systemName: "terminal")
					}
				}
			}

			if isModuleSupported(.storeforwardConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.storeAndForward) {
					Label {
						Text("Store & Forward")
					} icon: {
						Image(systemName: "envelope.arrow.triangle.branch")
					}
				}
			}

			// Module Configuration → TAK routes to the combined TAK Server page
			// (TAKServerConfig). That screen renders the firmware module config
			// (team / role identity, via the embedded TAKIdentitySection) at
			// the top, and the in-app TAK Server controls (Enable, channel,
			// mTLS certificates, data package export) below it. The TAK
			// section at the bottom of this screen links to the same view.
			NavigationLink(value: SettingsNavigationState.tak) {
				Label {
					Text("TAK Server")
				} icon: {
					Image(systemName: "target")
				}
			}

			if isModuleSupported(.telemetryConfig, excludedModules: excludedModules) {
				NavigationLink(value: SettingsNavigationState.telemetry) {
					Label {
						Text("Telemetry")
					} icon: {
						Image(systemName: "chart.xyaxis.line")
					}
				}
			}

			if isTrafficManagementModuleSupported(node) {
				NavigationLink(value: SettingsNavigationState.trafficManagement) {
					Label {
						Text("Traffic Management")
					} icon: {
						Image(systemName: "arrow.triangle.branch")
					}
				}
			}

			if !showsAnyModuleConfiguration(node: node, excludedModules: excludedModules) {
				Text("This node does not support any configurable modules.")
					.foregroundColor(.secondary)
			}
		} header: {
			Text("Module Configuration")
		}
	}

	var loggingSection: some View {
		Section(header: Text("Logging")) {
			NavigationLink(value: SettingsNavigationState.debugLogs) {
				Label {
					Text("Logs")
				} icon: {
					Image(systemName: "scroll")
				}
			}
			NavigationLink(value: SettingsNavigationState.traceRoutes) {
				Label {
					Text("Trace Routes")
				} icon: {
					Image(systemName: "point.3.connected.trianglepath.dotted")
				}
			}
		}
	}

	var developersSection: some View {
		Section(header: Text("Developers")) {
			NavigationLink(value: SettingsNavigationState.backupManagement) {
				Label {
					Text("Backup Management")
				} icon: {
					Image(systemName: "externaldrive")
				}
			}
			NavigationLink(value: SettingsNavigationState.coreDataBrowser) {
				Label {
					Text("Data Browser")
				} icon: {
					Image(systemName: "tablecells")
				}
			}
			NavigationLink(value: SettingsNavigationState.deviceLinks) {
				Label {
					Text("Device Links")
				} icon: {
					Image(systemName: "link")
				}
			}
			NavigationLink(value: SettingsNavigationState.appFiles) {
				Label {
					Text("App Files")
				} icon: {
					Image(systemName: "folder")
				}
			}
			// Tools hosts NFC actions AND device-configuration import/export. Gating the whole entry
			// point on NFC hardware made sense while it was NFC-only, but it now hides import/export
			// completely on iPad, Mac Catalyst, and the Simulator, with no other way to reach them.
			// Show it when either capability is usable; Tools itself hides the sections that are not.
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 18, *) {
				if NFCReader.isAvailable || accessoryManager.isConnected {
					NavigationLink(value: SettingsNavigationState.tools) {
						Label {
							Text("Tools")
						} icon: {
							Image(systemName: "hammer")
						}
					}
				}
			}
			#endif
		}
	}

	var takSection: some View {
		Section(header: Text("TAK")) {
			// Routes to the same combined TAK Server page reached via the
			// Module Configuration section above. Both entry points are kept
			// because users naturally look in both places when configuring
			// TAK — the Module Config link discovers the feature alongside
			// other module configs, and the dedicated TAK section advertises
			// the TAK Server functionality at a glance.
			NavigationLink(value: SettingsNavigationState.tak) {
				Label {
					Text("TAK Server")
				} icon: {
					Image(systemName: "target")
				}
			}
		}
	}

	var body: some View {
		NavigationStack(
			path: $router.settingsPath
		) {
			let node = nodeSnapshot(for: preferredNodeNum)
			List {
				NavigationLink(value: SettingsNavigationState.about) {
					Label {
						Text("About Meshtastic")
					} icon: {
						Image(systemName: "questionmark.app")
					}
				}

				NavigationLink(value: SettingsNavigationState.helpDocs) {
					Label {
						Text("Help & Documentation")
					} icon: {
						Image(systemName: "book.pages")
					}
				}

				NavigationLink(value: SettingsNavigationState.appSettings) {
					Label {
						Text("App Settings")
					} icon: {
						Image(systemName: "gearshape")
					}
				}
				NavigationLink(value: SettingsNavigationState.localMeshDiscovery) {
					Label {
						Text("Local Mesh Discovery")
					} icon: {
						Image(systemName: "antenna.radiowaves.left.and.right")
					}
				}
				NavigationLink(value: SettingsNavigationState.routes) {
					Label {
						Text("Routes")
					} icon: {
						Image(systemName: "road.lanes.curved.right")
					}
				}

				NavigationLink(value: SettingsNavigationState.routeRecorder) {
					Label {
						Text("Route Recorder")
					} icon: {
						Image(systemName: "record.circle")
							.foregroundColor(.red)
					}
				}
				NavigationLink(value: SettingsNavigationState.firmwareUpdates) {
					Label {
						Text("Firmware Updates")
					} icon: {
						Image(systemName: "arrow.up.arrow.down.square")
					}
				}
				.disabled(selectedNode > 0 && selectedNode != preferredNodeNum)

				// A managed radio hides the configuration sections; say why instead of
				// showing nothing (same message as Android).
				if let node, node.isManaged, accessoryManager.isConnected {
					Section("Configure") {
						Label("This radio is managed and can only be changed by a remote admin.", systemImage: "lock.shield")
							.font(.callout)
							.foregroundStyle(.orange)
					}
				}
				if let node, !node.isManaged {
					if accessoryManager.isConnected {
						Section("Configure") {
							if node.canRemoteAdmin {
								Picker("Node", selection: $selectedNode) {
									if selectedNode == 0 {
										Text("Connect to a Node").tag(0)
									}
									ForEach(sortedNodes) { node in
										/// Connected Node
										if node.num == accessoryManager.activeDeviceNum ?? 0 {
											Label {
												Text("Connected") + Text(verbatim: ": \(node.userLongName?.addingVariationSelectors ?? "Unknown".localized)")
											} icon: {
												accessoryManager.activeConnection?.device.transportType.icon ?? Image(systemName: "questionmark.circle")
											}
											.tag(Int(node.num))
										} else if node.canRemoteAdmin && UserDefaults.enableAdministration && node.hasSessionPasskey { /// Nodes using the new PKI or signed system
											let presentation = RemoteAdminWording.activePresentation(localOwnerIsLicensed: localOwnerIsLicensed)
											Label {
												Text(String.localizedStringWithFormat(
													presentation.format.localized,
													node.userLongName ?? "Unknown".localized
												))
											} icon: {
												Image(systemName: presentation.systemImage)
											}
											.font(.caption2)
											.tag(Int(node.num))
										} else if !UserDefaults.enableAdministration && node.hasMetadata { /// Nodes using the old admin system
											Label {
												Text("Remote Legacy Admin: \(node.userLongName ?? "Unknown".localized)")
											} icon: {
												Image(systemName: "av.remote")
											}
											.tag(Int(node.num))
										} else if UserDefaults.enableAdministration && node.userIsPkiEncrypted {
											Label {
												Text(String.localizedStringWithFormat(
													RemoteAdminWording.requestFormat(localOwnerIsLicensed: localOwnerIsLicensed).localized,
													node.userLongName?.addingVariationSelectors ?? "Unknown".localized
												))
											} icon: {
												Image(systemName: "rectangle.and.hand.point.up.left")
											}
											.tag(Int(node.num))
										} else if !UserDefaults.enableAdministration {
											Label {
												Text("Request Legacy Admin: \(node.userLongName?.addingVariationSelectors ?? "Unknown".localized)")
											} icon: {
												Image(systemName: "rectangle.and.hand.point.up.left")
											}
											.tag(Int(node.num))
									}
								}
								}
								.pickerStyle(.navigationLink)
								.onChange(of: selectedNode) { _, newValue in
									handleSelectedNodeChange(newValue)
								}
								TipView(AdminChannelTip(), arrowEdge: .top)
									.tipViewStyle(PersistentTipStyle())
									.tipBackground(colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground))
									.listRowSeparator(.hidden)
							} else {
								if accessoryManager.isConnected {
									Text("Connected Node \(node.userLongName?.addingVariationSelectors ?? "Unknown".localized)")
								}
							}
						}
					}
					radioConfigurationSection
					deviceConfigurationSection
					moduleConfigurationSection
					loggingSection
					if showsDevelopersSection {
					developersSection
					}
				}
			}
			.navigationDestination(for: SettingsNavigationState.self) { destination in
				let node = liveNode(for: preferredNodeNum)
				let configNode = liveNode(for: selectedNode)
				switch destination {
				case .about:
					AboutMeshtastic()
				case .appSettings:
					AppSettings()
				case .routes:
					Routes()
				case .routeRecorder:
					RouteRecorder()
				case .lora:
					LoRaConfig(node: configNode)
				case .channels:
					if let node = node {
						Channels(node: node)
					} else {
						Text("Loading...")
					}
				case .shareQRCode:
					ShareChannels(node: node)
				case .user:
					UserConfig(node: configNode)
				case .bluetooth:
					BluetoothConfig(node: configNode)
				case .device:
					DeviceConfig(node: configNode)
				case .display:
					DisplayConfig(node: configNode)
				case .network:
					NetworkConfig(node: configNode)
				case .position:
					PositionConfig(node: configNode)
				case .power:
					PowerConfig(node: configNode)
				case .ambientLighting:
					AmbientLightingConfig(node: node)
				case .audio:
					AudioConfig(node: configNode)
				case .cannedMessages:
					CannedMessagesConfig(node: configNode)
				case .detectionSensor:
					DetectionSensorConfig(node: configNode)
				case .meshBeacon:
					MeshBeaconConfig(node: configNode)
				case .externalNotification:
					ExternalNotificationConfig(node: configNode)
				case .mqtt:
					MQTTConfig(node: configNode)
				case .neighborInfo:
					NeighborInfoConfig(node: configNode)
				case .rangeTest:
					RangeTestConfig(node: configNode)
				case .paxCounter:
					PaxCounterConfig(node: configNode)
				case .ringtone:
					RtttlConfig(node: configNode)
				case .security:
					SecurityConfig(node: configNode)
				case .serial:
					SerialConfig(node: configNode)
				case .storeAndForward:
					StoreForwardConfig(node: configNode)
				case .telemetry:
					TelemetryConfig(node: configNode)
				case .trafficManagement:
					TrafficManagementConfig(node: configNode)
				case .debugLogs:
					AppLog()
				case .traceRoutes:
					AllTraceRoutesLog()
				case .appFiles:
					AppData()
				case .firmwareUpdates:
					Firmware(node: node)
				case .deviceLinks:
					DeviceLinkDirectory()
				case .tools:
					if #available(iOS 18, *) {
						Tools()
					}
				case .tak:
					TAKServerConfig()
				case .takConfig:
					TAKModuleConfig(node: configNode)
				case .coreDataBrowser:
					CoreDataBrowser()
				case .localMeshDiscovery:
					DiscoveryScanView()
				case .helpDocs:
					DocBrowserView()
				case .backupManagement:
					BackupManagement()
				}
			}
			.onChange(of: UserDefaults.preferredPeripheralNum ) { _, newConnectedNode in
				// If the preferred node changes, then select the newly preferred node
				// This should only happen during connect
				preferredNodeNum = newConnectedNode
				selectedNode = Int(accessoryManager.isConnected ? newConnectedNode : 0)
			}
			.onChange(of: accessoryManager.isConnected) { _, isConnectedNow in
				// If we are on this screen, haven't iniatialized the selection yet,
				// And we transition, to connected, then initialize the selection
				if isConnectedNow, self.selectedNode == 0 {
					self.preferredNodeNum = UserDefaults.preferredPeripheralNum
					setSelectedNode(to: UserDefaults.preferredPeripheralNum)
				}
			}
			.onChange(of: accessoryManager.activeDeviceNum) { oldDevice, newDevice in
				if newDevice == nil {
					selectedNode = 0
					preferredNodeNum = 0
				} else if oldDevice != newDevice {
					// Physical connection changed — any prior remote admin session is invalid
					preferredNodeNum = Int(newDevice!)
					selectedNode = Int(newDevice!)
				}
			}
			.onAppear {
				// If the selection hasn't be initialized yet, try to initalize it.
				// If we are not fully connected yet, then setSelectedNode will
				// not select the node and it will remain 0
				refreshNodes()
				if self.preferredNodeNum <= 0 {
					self.preferredNodeNum = UserDefaults.preferredPeripheralNum
					setSelectedNode(to: UserDefaults.preferredPeripheralNum)
				}
			}
			.task(id: router.selectedTab) {
				// Refresh the node snapshot on a gentle cadence, and only while Settings is
				// the frontmost tab — the stale snapshot is invisible from other tabs, this
				// task re-fires on every tab switch (so the guard comes first), and switching
				// here restarts it for an immediate refresh.
				guard router.selectedTab == .settings else { return }
				refreshNodes()
				while !Task.isCancelled {
					do {
						try await Task.sleep(for: .seconds(2))
					} catch {
						break
					}
					guard !Task.isCancelled else { break }
					refreshNodes()
				}
			}
			.navigationTitle("Settings")
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					MeshtasticLogo().onLongPressGesture(minimumDuration: 1.0) {
					}
				}
			}
		}
	}

	func setSelectedNode(to nodeNum: Int) {
		guard nodeSnapshot(for: nodeNum) != nil else {
			selectedNode = 0
			return
		}

		if sortedNodes.count > 1 {
			if selectedNode == 0 {
				self.selectedNode = Int(accessoryManager.isConnected ? nodeNum : 0)
			}
		} else {
			self.selectedNode = Int(accessoryManager.isConnected ? nodeNum: 0)
		}
	}

	private func handleSelectedNodeChange(_ newValue: Int) {
		guard selectedNode > 0,
			let destinationNode = liveNode(for: newValue),
			let connectedNode = liveNode(for: preferredNodeNum),
			let fromUser = connectedNode.user,
			connectedNode.myInfo != nil,
			let toUser = destinationNode.user else { return }

		preferredNodeNum = Int(connectedNode.num)
		Task {
			_ = try await accessoryManager.requestDeviceMetadata(fromUser: fromUser, toUser: toUser)
			Task { @MainActor in
				Logger.mesh.info("Sent node metadata request from node details")
			}
		}
	}
}
