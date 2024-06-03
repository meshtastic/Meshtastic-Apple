//
//  Settings.swift
//  MeshtasticApple
//
//  Copyright (c) Garth Vander Houwen 6/9/22.
//

import SwiftUI
import OSLog
#if canImport(TipKit)
import TipKit
#endif

struct Settings: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "favorite", ascending: false),
									NSSortDescriptor(key: "user.longName", ascending: true)], animation: .default)
	private var nodes: FetchedResults<NodeInfoEntity>
	@State private var selectedNode: Int = 0
	@State private var preferredNodeNum: Int = 0
	@State private var selection: SettingsSidebar = .about
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
	}
	var body: some View {
		NavigationSplitView {
			List {
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
				if #available(iOS 17.0, macOS 14.0, *) {
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

				let node = nodes.first(where: { $0.num == preferredNodeNum })
				let hasAdmin = node?.myInfo?.adminIndex ?? 0 > 0 ? true : false

				if !(node?.deviceConfig?.isManaged ?? false) {
					if bleManager.connectedPeripheral != nil {
						Section("Configure") {
							if hasAdmin {
								Picker("Configuring Node", selection: $selectedNode) {
									if selectedNode == 0 {
										Text("Connect to a Node").tag(0)
									}

									ForEach(nodes) { node in
										if node.num == bleManager.connectedPeripheral?.num ?? 0 {
											Label {
												Text("BLE: \(node.user?.longName ?? "unknown".localized)")
											} icon: {
												Image(systemName: "antenna.radiowaves.left.and.right")
											}
											.tag(Int(node.num))
										} else if node.metadata != nil {
											Label {
												Text("Remote: \(node.user?.longName ?? "unknown".localized)")
											} icon: {
												Image(systemName: "av.remote")
											}
											.tag(Int(node.num))
										} else if hasAdmin {
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
								.onChange(of: selectedNode) { newValue in
									if selectedNode > 0 {
										let node = nodes.first(where: { $0.num == newValue })
										let connectedNode = nodes.first(where: { $0.num == preferredNodeNum })
										preferredNodeNum = Int(connectedNode?.num ?? 0)// Int(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral?.num ?? 0 : 0)
										if connectedNode != nil && connectedNode?.user != nil && connectedNode?.myInfo != nil && node?.user != nil && node?.metadata == nil {
											let adminMessageId =  bleManager.requestDeviceMetadata(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode!.myInfo!.adminIndex, context: context)
											if adminMessageId > 0 {
												Logger.mesh.info("Sent node metadata request from node details")
											}
										}
									}
								}
								if #available(iOS 17.0, macOS 14.0, *) {
									TipView(AdminChannelTip(), arrowEdge: .top)
								}
							} else {
								if bleManager.connectedPeripheral != nil {
									Text("Connected Node \(node?.user?.longName ?? "unknown".localized)")
								}
							}
						}
					}
					Section("radio.configuration") {
						if node != nil && node?.loRaConfig != nil {
							let rc = RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))
							if rc?.dutyCycle ?? 0 > 0 && rc?.dutyCycle ?? 0 < 100 {

								Label {
									Text("Hourly Duty Cycle")
								} icon: {
									Image(systemName: "clock.arrow.circlepath")
										.symbolRenderingMode(.hierarchical)
										.foregroundColor(.red)
								}
								Text("Your region has a \(rc?.dutyCycle ?? 0)% hourly duty cycle, your radio will stop sending packets when it reaches the hourly limit.")
									.foregroundColor(.orange)
									.font(.caption)
								Text("Limit all periodic broadcast intervals especially telemetry and position. If you need to increase hops, do it on nodes at the edges, not the ones in the middle. MQTT is not advised when you are duty cycle restricted because the gateway node is then doing all the work.")
									.font(.caption2)
									.foregroundColor(.gray)
							}
						}
						NavigationLink {
							LoRaConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("lora")
							} icon: {
								Image(systemName: "dot.radiowaves.left.and.right")
									.rotationEffect(.degrees(-90))
							}
						}
						.tag(SettingsSidebar.loraConfig)
						NavigationLink {
							Channels(node: nodes.first(where: { $0.num == preferredNodeNum }))
						} label: {
							Label {
								Text("channels")
							} icon: {
								Image(systemName: "fibrechannel")
							}
						}
						.tag(SettingsSidebar.channelConfig)
						.disabled(selectedNode > 0 && selectedNode != preferredNodeNum)
						NavigationLink {
							ShareChannels(node: nodes.first(where: { $0.num == preferredNodeNum }))
						} label: {
							Label {
								Text("share.channels")
							} icon: {
								Image(systemName: "qrcode")
							}
						}
						.tag(SettingsSidebar.shareChannels)
						.disabled(selectedNode > 0 && selectedNode != preferredNodeNum)
					}
					Section("device.configuration") {
						NavigationLink {
							UserConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("user")
							} icon: {
								Image(systemName: "person.crop.rectangle.fill")
							}
						}
						.tag(SettingsSidebar.userConfig)
						NavigationLink {
							BluetoothConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("bluetooth")
							} icon: {
								Image(systemName: "antenna.radiowaves.left.and.right")
							}
						}
						.tag(SettingsSidebar.bluetoothConfig)
						NavigationLink {
							DeviceConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("device")
							} icon: {
								Image(systemName: "flipphone")
							}
						}
						.tag(SettingsSidebar.deviceConfig)
						NavigationLink {
							DisplayConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("display")
							} icon: {
								Image(systemName: "display")
							}
						}
						.tag(SettingsSidebar.displayConfig)
						NavigationLink {
							NetworkConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("network")
							} icon: {
								Image(systemName: "network")
							}
						}
						.tag(SettingsSidebar.networkConfig)
						NavigationLink {
							PositionConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("position")
							} icon: {
								Image(systemName: "location")
							}
						}
						.tag(SettingsSidebar.positionConfig)

						NavigationLink {
							PowerConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("config.power.settings")
							} icon: {
								Image(systemName: "bolt.fill")
							}
						}
						.tag(SettingsSidebar.powerConfig)
					}
					Section("module.configuration") {
						if #available(iOS 17.0, macOS 14.0, *) {
							NavigationLink {
								AmbientLightingConfig(node: nodes.first(where: { $0.num == selectedNode }))
							} label: {
								Label {
									Text("ambient.lighting")
								} icon: {
									Image(systemName: "light.max")
								}
							}
							.tag(SettingsSidebar.ambientLightingConfig)
						}
						NavigationLink {
							CannedMessagesConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("canned.messages")
							} icon: {
								Image(systemName: "list.bullet.rectangle.fill")
							}
						}
						.tag(SettingsSidebar.cannedMessagesConfig)
						NavigationLink {
							DetectionSensorConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("detection.sensor")
							} icon: {
								Image(systemName: "sensor")
							}
						}
						.tag(SettingsSidebar.detectionSensorConfig)
						NavigationLink {
							ExternalNotificationConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("external.notification")
							} icon: {
								Image(systemName: "megaphone")
							}
						}
						.tag(SettingsSidebar.externalNotificationConfig)
						NavigationLink {
							MQTTConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("mqtt")
							} icon: {
								Image(systemName: "dot.radiowaves.up.forward")
							}
						}
						.tag(SettingsSidebar.mqttConfig)
						NavigationLink {
							RangeTestConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("range.test")
							} icon: {
								Image(systemName: "point.3.connected.trianglepath.dotted")
							}
						}
						.tag(SettingsSidebar.rangeTestConfig)
						if node?.metadata?.hasWifi ?? false {
							NavigationLink {
								PaxCounterConfig(node: nodes.first(where: { $0.num == selectedNode }))
							} label: {
								Label {
									Text("config.module.paxcounter.settings")
								} icon: {
									Image(systemName: "figure.walk.motion")
								}
							}
							.tag(SettingsSidebar.paxCounterConfig)
						}
						NavigationLink {
							RtttlConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("ringtone")
							} icon: {
								Image(systemName: "music.note.list")
							}
						}
						.tag(SettingsSidebar.ringtoneConfig)
						NavigationLink {
							SerialConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("serial")
							} icon: {
								Image(systemName: "terminal")
							}
						}
						.tag(SettingsSidebar.serialConfig)
						NavigationLink {
							StoreForwardConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("storeforward")
							} icon: {
								Image(systemName: "envelope.arrow.triangle.branch")
							}
						}
						.tag(SettingsSidebar.storeAndForwardConfig)
						NavigationLink {
							TelemetryConfig(node: nodes.first(where: { $0.num == selectedNode }))
						} label: {
							Label {
								Text("telemetry")
							} icon: {
								Image(systemName: "chart.xyaxis.line")
							}
						}
						.tag(SettingsSidebar.telemetryConfig)
					}
					Section(header: Text("logging")) {
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
						NavigationLink {
							let connectedNode = nodes.first(where: { $0.num == preferredNodeNum })
							AdminMessageList(user: connectedNode?.user)
						} label: {
							Label {
								Text("admin.log")
							} icon: {
								Image(systemName: "building.columns")
							}
						}
						.tag(SettingsSidebar.adminMessageLog)
					}
					Section(header: Text("Firmware")) {
						NavigationLink {
							Firmware(node: nodes.first(where: { $0.num == preferredNodeNum }))
						} label: {
							Label {
								Text("Firmware Updates")
							} icon: {
								Image(systemName: "arrow.up.arrow.down.square")
							}
						}
						.tag(SettingsSidebar.about)
						.disabled(selectedNode > 0 && selectedNode != preferredNodeNum)
					}
				}
			}
			.onChange(of: UserDefaults.preferredPeripheralNum ) { newConnectedNode in
				preferredNodeNum = newConnectedNode
				if nodes.count > 1 {
					if selectedNode == 0 {
						self.selectedNode = Int(bleManager.connectedPeripheral != nil ? newConnectedNode : 0)
					}
				} else {
					self.selectedNode = Int(bleManager.connectedPeripheral != nil ? newConnectedNode: 0)
				}
			}
			.onAppear {
				if self.preferredNodeNum <= 0 {
					self.preferredNodeNum = UserDefaults.preferredPeripheralNum
					if nodes.count > 1 {
						if selectedNode == 0 {
							self.selectedNode = Int(bleManager.connectedPeripheral != nil ? UserDefaults.preferredPeripheralNum : 0)
						}
					} else {
						self.selectedNode = Int(bleManager.connectedPeripheral != nil ? UserDefaults.preferredPeripheralNum : 0)
					}
				}
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("settings")
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
		}
		detail: {
			if #available (iOS 17, *) {
				ContentUnavailableView("select.menu.item", systemImage: "gear")
			} else {
				Text("select.menu.item")
			}
		}
	}
}
