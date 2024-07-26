//
//  Settings.swift
//  MeshtasticApple
//
//  Copyright (c) Garth Vander Houwen 6/9/22.
//

import SwiftUI
import OSLog

struct Settings: View {
	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var selectedNodeNum: Int = 0
	@State
	private var connectedNodeNum: Int = 0
	@State
	private var selection: SettingsSidebar = .about

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var nodeSelected: NodeInfoEntity? {
		nodes.first(where: { node in
			node.num == selectedNodeNum
		})
	}

	private var nodeConnected: NodeInfoEntity? {
		nodes.first(where: { node in
			node.num == connectedNodeNum
		})
	}

	private var nodeIsConnected: Bool {
		selectedNodeNum > 0 && selectedNodeNum != connectedNodeNum
	}

	private var nodeHasAdmin: Bool {
		guard let myInfo = nodeConnected?.myInfo else {
			return false
		}

		return myInfo.adminIndex > 0
	}

	private var nodeIsManaged: Bool {
		guard let config = nodeConnected?.deviceConfig else {
			return false
		}

		return config.isManaged
	}

	enum SettingsSidebar {
		case appSettings
		case routes
		case routeRecorder
		case shareChannels
		case userConfig
		case loraConfig
		case channelConfig
		case bluetoothConfig
		case deviceConfig
		case displayConfig
		case networkConfig
		case paxCounterConfig
		case positionConfig
		case powerConfig
		case ambientLightingConfig
		case cannedMessagesConfig
		case detectionSensorConfig
		case externalNotificationConfig
		case mqttConfig
		case rangeTestConfig
		case ringtoneConfig
		case serialConfig
		case storeAndForwardConfig
		case telemetryConfig
		case meshLog
		case adminMessageLog
		case about
		case appLog
		case appData
	}

	@ViewBuilder
	var body: some View {
		NavigationSplitView {
			List {
				about
				settings
				routes
				routeRecorder

				if !nodeIsManaged {
					if bleManager.connectedPeripheral != nil {
						sectionConfigure
					}

					sectionRadio
					sectionDevice
					sectionModule

					logging
					firmware
				}
			}
			.listStyle(.insetGrouped)
			.onChange(of: UserDefaults.preferredPeripheralNum, initial: true) {
				connectedNodeNum = UserDefaults.preferredPeripheralNum

				if nodes.count > 1 {
					if selectedNodeNum == 0 {
						selectedNodeNum = Int(bleManager.connectedPeripheral != nil ? connectedNodeNum : 0)
					}
				}
				else {
					selectedNodeNum = Int(bleManager.connectedPeripheral != nil ? connectedNodeNum: 0)
				}
			}
			.navigationTitle("settings")
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
		}
		detail: {
			ContentUnavailableView("select.menu.item", systemImage: "gear")
		}
	}

	@ViewBuilder
	private var about: some View {
		NavigationLink {
			AboutMeshtastic()
		} label: {
			Label {
				Text("about.meshtastic")
			} icon: {
				Image(systemName: "questionmark.app")
			}
		}
		.tag(SettingsSidebar.about)
	}

	@ViewBuilder
	private var settings: some View {
		NavigationLink {
			AppSettings()
		} label: {
			Label {
				Text("appsettings")
			} icon: {
				Image(systemName: "gearshape")
			}
		}
		.tag(SettingsSidebar.appSettings)
	}

	@ViewBuilder
	private var routes: some View {
		NavigationLink {
			Routes()
		} label: {
			Label {
				Text("routes")
			} icon: {
				Image(systemName: "road.lanes.curved.right")
			}
		}
		.tag(SettingsSidebar.routes)
	}

	@ViewBuilder
	private var routeRecorder: some View {
		NavigationLink {
			RouteRecorder()
		} label: {
			Label {
				Text("route.recorder")
			} icon: {
				Image(systemName: "record.circle")
					.foregroundColor(.red)
			}
		}
		.tag(SettingsSidebar.routeRecorder)
	}

	@ViewBuilder
	private var logging: some View {
		NavigationLink {
			MeshLog()
		} label: {
			Label {
				Text("mesh.log")
			} icon: {
				Image(systemName: "list.bullet.rectangle")
			}
		}
		.tag(SettingsSidebar.meshLog)
	}

	@ViewBuilder
	private var firmware: some View {
		NavigationLink {
			Firmware(node: nodeConnected)
		} label: {
			Label {
				Text("Firmware Updates")
			} icon: {
				Image(systemName: "arrow.up.arrow.down.square")
			}
		}
		.tag(SettingsSidebar.about)
		.disabled(!nodeIsConnected)
	}

	@ViewBuilder
	private var sectionConfigure: some View {
		Section("Configure") {
			if nodeHasAdmin {
				Picker("Configuring Node", selection: $selectedNodeNum) {
					if selectedNodeNum == 0 {
						Text("Connect to a Node")
							.tag(0)
					}

					ForEach(nodes) { node in
						if node.num == bleManager.connectedPeripheral?.num ?? 0 {
							Label {
								Text("BLE: \(node.user?.longName ?? "unknown".localized)")
							} icon: {
								Image(systemName: "antenna.radiowaves.left.and.right")
							}
							.tag(Int(node.num))
						}
						else if node.metadata != nil {
							Label {
								Text("Remote: \(node.user?.longName ?? "unknown".localized)")
							} icon: {
								Image(systemName: "av.remote")
							}
							.tag(Int(node.num))
						}
						else if nodeHasAdmin {
							Label {
								Text("Request Admin: \(node.user?.longName ?? "unknown".localized)")
							} icon: {
								Image(systemName: "rectangle.and.hand.point.up.left")
							}
							.tag(Int(node.num))
						}
					}
				}
				.pickerStyle(.automatic)
				.labelsHidden()
				.onChange(of: selectedNodeNum) {
					if selectedNodeNum > 0 {
						connectedNodeNum = Int(nodeConnected?.num ?? 0)

						if
							let nodeConnected,
							let user = nodeConnected.user,
							let myInfo = nodeConnected.myInfo,
							let userSelected = nodeSelected?.user
						{
							let adminMessageId =  bleManager.requestDeviceMetadata(
								fromUser: user,
								toUser: userSelected,
								adminIndex: myInfo.adminIndex,
								context: context
							)

							if adminMessageId > 0 {
								Logger.mesh.info("Sent node metadata request from node details")
							}
						}
					}
				}
			} else {
				if bleManager.connectedPeripheral != nil {
					Text("Connected Node \(nodeConnected?.user?.longName ?? "unknown".localized)")
				}
			}
		}
	}

	@ViewBuilder
	private var sectionRadio: some View {
		Section("Radio") {
			NavigationLink {
				LoRaConfig(node: nodeSelected)
			} label: {
				Label {
					Text("LoRa")
				} icon: {
					Image(systemName: "dot.radiowaves.left.and.right")
						.rotationEffect(.degrees(-90))
				}
			}
			.tag(SettingsSidebar.loraConfig)

			NavigationLink {
				Channels(node: nodeSelected)
			} label: {
				Label {
					Text("Channels")
				} icon: {
					Image(systemName: "fibrechannel")
				}
			}
			.tag(SettingsSidebar.channelConfig)
			.disabled(nodeIsConnected)

			NavigationLink {
				ShareChannels(node: nodeConnected)
			} label: {
				Label {
					Text("Share Channels")
				} icon: {
					Image(systemName: "qrcode")
				}
			}
			.tag(SettingsSidebar.shareChannels)
			.disabled(nodeIsConnected)
		}
	}

	@ViewBuilder
	private var sectionDevice: some View {
		Section("Device") {
			NavigationLink {
				UserConfig(node: nodeSelected)
			} label: {
				Label {
					Text("User")
				} icon: {
					Image(systemName: "person.crop.rectangle.fill")
				}
			}
			.tag(SettingsSidebar.userConfig)

			NavigationLink {
				BluetoothConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Bluetooth")
				} icon: {
					Image(systemName: "antenna.radiowaves.left.and.right")
				}
			}
			.tag(SettingsSidebar.bluetoothConfig)

			NavigationLink {
				DeviceConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Device")
				} icon: {
					Image(systemName: "flipphone")
				}
			}
			.tag(SettingsSidebar.deviceConfig)

			NavigationLink {
				DisplayConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Display")
				} icon: {
					Image(systemName: "display")
				}
			}
			.tag(SettingsSidebar.displayConfig)

			NavigationLink {
				NetworkConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Network")
				} icon: {
					Image(systemName: "network")
				}
			}
			.tag(SettingsSidebar.networkConfig)

			NavigationLink {
				PositionConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Location")
				} icon: {
					Image(systemName: "location")
				}
			}
			.tag(SettingsSidebar.positionConfig)

			NavigationLink {
				PowerConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Power Settings")
				} icon: {
					Image(systemName: "bolt.fill")
				}
			}
			.tag(SettingsSidebar.powerConfig)
		}
	}
	
	@ViewBuilder
	private var sectionModule: some View {
		Section("Module") {
			NavigationLink {
				AmbientLightingConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Ambient Lightning")
				} icon: {
					Image(systemName: "light.max")
				}
			}
			.tag(SettingsSidebar.ambientLightingConfig)

			NavigationLink {
				CannedMessagesConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Canned Messages")
				} icon: {
					Image(systemName: "list.bullet.rectangle.fill")
				}
			}
			.tag(SettingsSidebar.cannedMessagesConfig)

			NavigationLink {
				DetectionSensorConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Detection Sensor")
				} icon: {
					Image(systemName: "sensor")
				}
			}
			.tag(SettingsSidebar.detectionSensorConfig)

			NavigationLink {
				ExternalNotificationConfig(node: nodeSelected)
			} label: {
				Label {
					Text("External Notifications")
				} icon: {
					Image(systemName: "megaphone")
				}
			}
			.tag(SettingsSidebar.externalNotificationConfig)

			NavigationLink {
				MQTTConfig(node: nodeSelected)
			} label: {
				Label {
					Text("MQTT")
				} icon: {
					Image(systemName: "dot.radiowaves.up.forward")
				}
			}
			.tag(SettingsSidebar.mqttConfig)

			NavigationLink {
				RangeTestConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Range Test")
				} icon: {
					Image(systemName: "point.3.connected.trianglepath.dotted")
				}
			}
			.tag(SettingsSidebar.rangeTestConfig)

			if nodeConnected?.metadata?.hasWifi ?? false {
				NavigationLink {
					PaxCounterConfig(node: nodeSelected)
				} label: {
					Label {
						Text("PAX Counter")
					} icon: {
						Image(systemName: "figure.walk.motion")
					}
				}
				.tag(SettingsSidebar.paxCounterConfig)
			}

			NavigationLink {
				RtttlConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Ringtone")
				} icon: {
					Image(systemName: "music.note.list")
				}
			}
			.tag(SettingsSidebar.ringtoneConfig)

			NavigationLink {
				SerialConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Serial")
				} icon: {
					Image(systemName: "terminal")
				}
			}
			.tag(SettingsSidebar.serialConfig)

			NavigationLink {
				StoreForwardConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Storeforward")
				} icon: {
					Image(systemName: "envelope.arrow.triangle.branch")
				}
			}
			.tag(SettingsSidebar.storeAndForwardConfig)

			NavigationLink {
				TelemetryConfig(node: nodeSelected)
			} label: {
				Label {
					Text("Telemetry")
				} icon: {
					Image(systemName: "chart.xyaxis.line")
				}
			}
			.tag(SettingsSidebar.telemetryConfig)
		}
	}
}
