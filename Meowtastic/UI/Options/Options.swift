import FirebaseAnalytics
import OSLog
import SwiftUI

struct Options: View {
	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var connectedNodeNum: Int = 0
	@State
	private var preferredNodeNum: Int = 0

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
			node.num == connectedNodeNum
		})
	}

	private var nodeConnected: NodeInfoEntity? {
		nodes.first(where: { node in
			node.num == preferredNodeNum
		})
	}

	private var nodeIsConnected: Bool {
		connectedNodeNum > 0 && connectedNodeNum != preferredNodeNum
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

	@ViewBuilder
	var body: some View {
		NavigationStack {
			List {
				connection

				if !nodeIsManaged {
					nodeConfig
				}

				appConfig
			}
			.listStyle(.insetGrouped)
			.onChange(of: UserDefaults.preferredPeripheralNum, initial: true) {
				preferredNodeNum = UserDefaults.preferredPeripheralNum

				if !nodes.isEmpty {
					if connectedNodeNum == 0 {
						connectedNodeNum = Int(bleManager.deviceConnected != nil ? preferredNodeNum : 0)
					}
				}
				else {
					connectedNodeNum = Int(bleManager.deviceConnected != nil ? preferredNodeNum : 0)
				}
			}
			.navigationTitle("Options")
			.navigationBarItems(
				trailing: ConnectedDevice()
			)
		}
		.onAppear {
			Analytics.logEvent(AnalyticEvents.options.id, parameters: [:])
		}
	}

	@ViewBuilder
	private var connection: some View {
		NavigationLink {
			NavigationLazyView(
				Connect(node: nodeSelected)
			)
		} label: {
			Label {
				Text("Connection")
			} icon: {
				if nodeSelected != nil {
					Image(systemName: "wifi")
				}
				else {
					Image(systemName: "wifi.slash")
				}
			}
		}
	}

	@ViewBuilder
	private var nodeConfig: some View {
		Section("Node") {
			NavigationLink {
				NavigationLazyView(
					LoRaConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("LoRa")
				} icon: {
					Image(systemName: "wifi.circle")
				}
			}

			NavigationLink {
				NavigationLazyView(
					Channels(node: nodeSelected)
				)
			} label: {
				Label {
					Text("Channels")
				} icon: {
					Image(systemName: "bubble.left.and.bubble.right")
				}
			}
			.disabled(nodeIsConnected)

			NavigationLink {
				NavigationLazyView(
					UserConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("User")
				} icon: {
					Image(systemName: "person.text.rectangle")
				}
			}

			NavigationLink {
				NavigationLazyView(
					DeviceConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("Device")
				} icon: {
					Image(systemName: "flipphone")
				}
			}

			NavigationLink {
				NavigationLazyView(
					MQTTConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("MQTT")
				} icon: {
					Image(systemName: "network")
				}
			}

			NavigationLink {
				NavigationLazyView(
					BluetoothConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("Bluetooth")
				} icon: {
					Image(systemName: "iphone.gen3")
				}
			}

			NavigationLink {
				NavigationLazyView(
					NetworkConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("WiFi")
				} icon: {
					Image(systemName: "wifi.router")
				}
			}

			NavigationLink {
				NavigationLazyView(
					PositionConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("GPS")
				} icon: {
					Image(systemName: "mappin.and.ellipse")
				}
			}

			NavigationLink {
				NavigationLazyView(
					DisplayConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("Display")
				} icon: {
					Image(systemName: "display")
				}
			}

			NavigationLink {
				NavigationLazyView(
					PowerConfig(node: nodeSelected)
				)
			} label: {
				Label {
					Text("Power")
				} icon: {
					Image(systemName: "powercord")
				}
			}
		}
	}

	@ViewBuilder
	private var appConfig: some View {
		Section("Application") {
			NavigationLink {
				NavigationLazyView(
					AppSettings()
				)
			} label: {
				Label {
					Text("Settings")
				} icon: {
					Image(systemName: "gearshape")
				}
			}

			NavigationLink {
				NavigationLazyView(
					About()
				)
			} label: {
				Label {
					Text("About")
				} icon: {
					Image(systemName: "info")
				}
			}
		}
	}
}
