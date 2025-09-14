//
//  Settings.swift
//  MeshtasticApple
//
//  Copyright (c) Garth Vander Houwen 6/9/22.
//

import SwiftUI
import OSLog
import TipKit
import MeshtasticProtobufs

struct Settings: View {
	@Environment(\.managedObjectContext) var context
	@Environment(\.colorScheme) private var colorScheme
	@EnvironmentObject var accessoryManager: AccessoryManager
	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "user.pkiEncrypted", ascending: false),
			NSSortDescriptor(key: "viaMqtt", ascending: true),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	@State private var selectedNode: Int = 0
	@State private var preferredNodeNum: Int = 0

	@ObservedObject
	var router: Router

	// MARK: Helper

	private func isModuleSupported(_ module: ExcludedModules) -> Bool {
		return Int(nodes.first(where: { $0.num == preferredNodeNum })?.metadata?.excludedModules ?? Int32.zero) & module.rawValue == 0
	}

	private func isAnySupported(_ modules: [ExcludedModules]) -> Bool {
		return modules.map(isModuleSupported).contains(true)
	}

	// MARK: Views

	var radioConfigurationSection: some View {
		Section("Radio Configuration") {
			let node = nodes.first(where: { $0.num == preferredNodeNum })
			if let node,
				let loRaConfig = node.loRaConfig,
				let rc = RegionCodes(rawValue: Int(loRaConfig.regionCode)),
				let user = node.user,
				!user.isLicensed,
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
		Section {
			if isModuleSupported(.ambientlightingConfig) {
				NavigationLink(value: SettingsNavigationState.ambientLighting) {
					Label {
						Text("Ambient Lighting")
					} icon: {
						Image(systemName: "light.max")
					}
				}
			}

			if isModuleSupported(.cannedmsgConfig) {
				NavigationLink(value: SettingsNavigationState.cannedMessages) {
					Label {
						Text("Canned Messages")
					} icon: {
						Image(systemName: "list.bullet.rectangle.fill")
					}
				}
			}

			if isModuleSupported(.detectionsensorConfig) {
				NavigationLink(value: SettingsNavigationState.detectionSensor) {
					Label {
						Text("Detection Sensor")
					} icon: {
						Image(systemName: "sensor")
					}
				}
			}

			if isModuleSupported(.extnotifConfig) {
				NavigationLink(value: SettingsNavigationState.externalNotification) {
					Label {
						Text("External Notification")
					} icon: {
						Image(systemName: "megaphone")
					}
				}
			}

			if isModuleSupported(.mqttConfig) {
				NavigationLink(value: SettingsNavigationState.mqtt) {
					Label {
						Text("MQTT")
					} icon: {
						Image(systemName: "dot.radiowaves.up.forward")
					}
				}
			}

			if isModuleSupported(.rangetestConfig) {
				NavigationLink(value: SettingsNavigationState.rangeTest) {
					Label {
						Text("Range Test")
					} icon: {
						Image(systemName: "point.3.connected.trianglepath.dotted")
					}
				}
			}

			if isModuleSupported(.paxcounterConfig) {
				NavigationLink(value: SettingsNavigationState.paxCounter) {
					Label {
						Text("PAX Counter")
					} icon: {
						Image(systemName: "figure.walk.motion")
					}
				}
			}

			if isModuleSupported(.extnotifConfig) {
				NavigationLink(value: SettingsNavigationState.ringtone) {
					Label {
						Text("Ringtone")
					} icon: {
						Image(systemName: "music.note.list")
					}
				}
			}

			if isModuleSupported(.serialConfig) {
				NavigationLink(value: SettingsNavigationState.serial) {
					Label {
						Text("Serial")
					} icon: {
						Image(systemName: "terminal")
					}
				}
			}

			if isModuleSupported(.storeforwardConfig) {
				NavigationLink(value: SettingsNavigationState.storeAndForward) {
					Label {
						Text("Store & Forward")
					} icon: {
						Image(systemName: "envelope.arrow.triangle.branch")
					}
				}
			}

			if isModuleSupported(.telemetryConfig) {
				NavigationLink(value: SettingsNavigationState.telemetry) {
					Label {
						Text("Telemetry")
					} icon: {
						Image(systemName: "chart.xyaxis.line")
					}
				}
			}

			// Update this list with the modules that are shown above. If all are not supported
			// Then show a message.
			if !isAnySupported([.ambientlightingConfig, .cannedmsgConfig,
								.detectionsensorConfig, .extnotifConfig,
								.mqttConfig, .rangetestConfig, .paxcounterConfig,
								.audioConfig, .serialConfig, .storeforwardConfig,
								.telemetryConfig]) {
				Text("This node does not support any configurable modules.")
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
		}
	}

	var developersSection: some View {
		Section(header: Text("Developers")) {
			NavigationLink(value: SettingsNavigationState.appFiles) {
				Label {
					Text("App Files")
				} icon: {
					Image(systemName: "folder")
				}
			}
		}
	}

	var firmwareSection: some View {
		Section(header: Text("Firmware")) {
			NavigationLink(value: SettingsNavigationState.firmwareUpdates) {
				Label {
					Text("Firmware Updates")
				} icon: {
					Image(systemName: "arrow.up.arrow.down.square")
				}
			}
			.disabled(selectedNode > 0 && selectedNode != preferredNodeNum)
		}
	}

	var body: some View {
		NavigationStack(
			path: Binding<[SettingsNavigationState]>(
				get: {
					[router.navigationState.settings].compactMap { $0 }
				},
				set: { newPath in
					router.navigationState.settings = newPath.first
				}
			)
		) {
			let node = nodes.first(where: { $0.num == preferredNodeNum })
			List {
				NavigationLink(value: SettingsNavigationState.about) {
					Label {
						Text("About Meshtastic")
					} icon: {
						Image(systemName: "questionmark.app")
					}
				}

				NavigationLink(value: SettingsNavigationState.appSettings) {
					Label {
						Text("App Settings")
					} icon: {
						Image(systemName: "gearshape")
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

				if !(node?.deviceConfig?.isManaged ?? false) {
					if accessoryManager.isConnected {
						Section("Configure") {
							if node?.canRemoteAdmin ?? false {
								Picker("Node", selection: $selectedNode) {
									if selectedNode == 0 {
										Text("Connect to a Node").tag(0)
									}
									ForEach(nodes) { node in
										/// Connected Node
										if node.num == accessoryManager.activeDeviceNum ?? 0 {
											Label {
												Text("Connected") + Text(verbatim: ": \(node.user?.longName?.addingVariationSelectors ?? "Unknown".localized)")
											} icon: {
												accessoryManager.activeConnection?.device.transportType.icon ?? Image("questionmark.circle")
											}
											.tag(Int(node.num))
										} else if node.canRemoteAdmin && UserDefaults.enableAdministration && node.sessionPasskey != nil { /// Nodes using the new PKI system
											Label {
												Text("Remote PKI Admin: \(node.user?.longName ?? "Unknown".localized)")
											} icon: {
												Image(systemName: "av.remote")
											}
											.font(.caption2)
											.tag(Int(node.num))
										} else if  !UserDefaults.enableAdministration && node.metadata != nil { /// Nodes using the old admin system
											Label {
												Text("Remote Legacy Admin: \(node.user?.longName ?? "Unknown".localized)")
											} icon: {
												Image(systemName: "av.remote")
											}
											.tag(Int(node.num))
										} else if UserDefaults.enableAdministration && node.user?.pkiEncrypted ?? false {
											Label {
												Text("Request PKI Admin: \(node.user?.longName?.addingVariationSelectors ?? "Unknown".localized)")
											} icon: {
												Image(systemName: "rectangle.and.hand.point.up.left")
											}
											.tag(Int(node.num))
										} else if !UserDefaults.enableAdministration {
											Label {
												Text("Request Legacy Admin: \(node.user?.longName?.addingVariationSelectors ?? "Unknown".localized)")
											} icon: {
												Image(systemName: "rectangle.and.hand.point.up.left")
											}
											.tag(Int(node.num))
										}
									}
								}
								.pickerStyle(.navigationLink)
								.onChange(of: selectedNode) { _, newValue in
									if selectedNode > 0,
									   let destinationNode = nodes.first(where: { $0.num == newValue }),
									   let connectedNode = nodes.first(where: { $0.num == preferredNodeNum }),
									   let fromUser = connectedNode.user,
									   let _ = connectedNode.myInfo,  // not sure why, but this check was present in the initial code.
									   let toUser = destinationNode.user {

										preferredNodeNum = Int(connectedNode.num)
										Task {
											_ = try await accessoryManager.requestDeviceMetadata(fromUser: fromUser, toUser: toUser)
											Task { @MainActor in
												Logger.mesh.info("Sent node metadata request from node details")
											}
										}
									}
								}
								TipView(AdminChannelTip(), arrowEdge: .top)
									.tipViewStyle(PersistentTip())
									.tipBackground(colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground))
									.listRowSeparator(.hidden)
							} else {
								if accessoryManager.isConnected {
									Text("Connected Node \(node?.user?.longName?.addingVariationSelectors ?? "Unknown".localized)")
								}
							}
						}
					}
					radioConfigurationSection
					deviceConfigurationSection
					moduleConfigurationSection
					loggingSection
#if DEBUG
					developersSection
#endif
					firmwareSection
				}
			}
			.navigationDestination(for: SettingsNavigationState.self) { destination in
				let node = nodes.first(where: { $0.num == preferredNodeNum })
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
					LoRaConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .channels:
					Channels(node: node)
				case .shareQRCode:
					ShareChannels(node: node)
				case .user:
					UserConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .bluetooth:
					BluetoothConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .device:
					DeviceConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .display:
					DisplayConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .network:
					NetworkConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .position:
					PositionConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .power:
					PowerConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .ambientLighting:
					AmbientLightingConfig(node: node)
				case .cannedMessages:
					CannedMessagesConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .detectionSensor:
					DetectionSensorConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .externalNotification:
					ExternalNotificationConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .mqtt:
					MQTTConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .rangeTest:
					RangeTestConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .paxCounter:
					PaxCounterConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .ringtone:
					RtttlConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .security:
					SecurityConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .serial:
					SerialConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .storeAndForward:
					StoreForwardConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .telemetry:
					TelemetryConfig(node: nodes.first(where: { $0.num == selectedNode }))
				case .debugLogs:
					AppLog()
				case .appFiles:
					AppData()
				case .firmwareUpdates:
					Firmware(node: node)
				}
			}
			.onChange(of: UserDefaults.preferredPeripheralNum ) { _, newConnectedNode in
				// If the preferred node changes, then select the newly perferred node
				// This should only happen during connect
				preferredNodeNum = newConnectedNode
				setSelectedNode(to: newConnectedNode)
			}
			.onChange(of: accessoryManager.isConnected) { _, isConnectedNow in
				// If we are on this screen, haven't iniatialized the selection yet,
				// And we transition, to connected, then initialize the selection
				if isConnectedNow, self.selectedNode == 0 {
					self.preferredNodeNum = UserDefaults.preferredPeripheralNum
					setSelectedNode(to: UserDefaults.preferredPeripheralNum)
				}
			}
			.onAppear {
				// If the selection hasn't be initialized yet, try to initalize it.
				// If we are not fully connected yet, then setSelectedNode will
				// not select the node and it will remain 0
				if self.preferredNodeNum <= 0 {
					self.preferredNodeNum = UserDefaults.preferredPeripheralNum
					setSelectedNode(to: UserDefaults.preferredPeripheralNum)
				}
			}
			.navigationTitle("Settings")
			.navigationBarItems(
				leading: MeshtasticLogo().onLongPressGesture(minimumDuration: 1.0) {
				}
			)
		}
	}
	
	func setSelectedNode(to nodeNum: Int) {
		if nodes.count > 1 {
			if selectedNode == 0 {
				self.selectedNode = Int(accessoryManager.isConnected ? nodeNum : 0)
			}
		} else {
			self.selectedNode = Int(accessoryManager.isConnected ? nodeNum: 0)
		}
	}
}
