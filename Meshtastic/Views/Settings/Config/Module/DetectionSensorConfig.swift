//
//  DetectionSensorModule.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/16/23.
//
import MeshtasticProtobufs
import OSLog
import SwiftUI

enum DetectionSensorRole: String, CaseIterable, Equatable, Decodable {
	case sensor
	case client
	var description: String {
		switch self {
		case .sensor:
			return "Sensor"
		case .client:
			return "Client"
		}
	}
	var localized: String { self.rawValue.localized }
}

struct DetectionSensorConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges: Bool = false
	@AppStorage("detectionSensorRole") private var role: DetectionSensorRole = .sensor
	@AppStorage("enableDetectionNotifications") private var detectionNotificationsEnabled = false
	/// Module Config Settings
	@State var enabled = false
	@State var sendBell: Bool = false
	@State var name: String = ""
	@State var triggerType = 0
	@State var usePullup: Bool = false
	@State var minimumBroadcastSecs = 0
	@State var stateBroadcastSecs = 0
	@State var monitorPin = 0

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Detection Sensor", config: \.detectionSensorConfig, node: node, onAppear: setDetectionSensorValues)

				Section(header: Text("Options")) {

					Toggle(isOn: $enabled) {
						Label("Enabled", systemImage: "dot.radiowaves.right")
						Text("Enables the detection sensor module, it needs to be enabled on both the node with the sensor, and any nodes that you want to receive detection sensor text messages or view the detection sensor log and chart.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					if enabled {
						HStack {
							Picker(selection: $role, label: Text("Role")) {
								ForEach(DetectionSensorRole.allCases, id: \.self) { r in
									Text(r.description)
										.tag(r)
								}
							}
							.pickerStyle(SegmentedPickerStyle())
							.padding(.top, 5)
							.padding(.bottom, 5)
						}
					}
				}
				if enabled && role == .client {
					Section(header: Text("Client options")) {
						Toggle(isOn: $detectionNotificationsEnabled) {
							Label("Enable Notifications", systemImage: "bell.badge")
							Text("Detection sensor messages are received as text messages.  If you enable notifications you will recieve a notification for each detection message received and a corresponding unread message badge.")
						}
					}
				}
				if enabled && role == .sensor {
					Section(header: Text("Sensor options")) {
						Toggle(isOn: $sendBell) {
							Label("Send Bell", systemImage: "bell")
							Text("Send ASCII bell with alert message. Useful for triggering external notification on bell.")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))

						HStack {
							Label("Name", systemImage: "signature")
							TextField("Friendly name", text: $name, axis: .vertical)
								.foregroundColor(.gray)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.onChange(of: name) {
									var totalBytes = name.utf8.count
									// Only mess with the value if it is too big
									while totalBytes > 20 {
										name = String(name.dropLast())
										totalBytes = name.utf8.count
									}
								}
						}
						.listRowSeparator(.hidden)
						Text("Friendly name used to format message sent to mesh. Example: A name \"Motion\" would result in a message \"Motion detected\"")
							.font(.callout)
							.foregroundStyle(.gray)

						Picker("GPIO Pin to monitor", selection: $monitorPin) {
							ForEach(0..<49) {
								if $0 == 0 {
									Text("unset")
								} else {
									Text("Pin \($0)")
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())

						Picker("TriggerType", selection: $triggerType) {
							ForEach(TriggerTypes.allCases) { tt in
								Text(tt.name).tag(tt.rawValue)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						.listRowSeparator(.hidden)

						Toggle(isOn: $usePullup) {
							Label("Uses pullup resistor", systemImage: "arrow.up.to.line")
							Text("Whether or not use INPUT_PULLUP mode for GPIO pin. Only applicable if the board uses pull-up resistors on the pin")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
					Section(header: Text("update.interval")) {
						Picker("Minimum time between detection broadcasts", selection: $minimumBroadcastSecs) {
							ForEach(UpdateIntervals.allCases) { ui in
								Text(ui.description).tag(ui.rawValue)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						.listRowSeparator(.hidden)
						Text("Mininum time between detection broadcasts. Default is 45 seconds.")
							.font(.callout)
							.foregroundStyle(.gray)
							.listRowSeparator(.visible)
						Picker("State Broadcast Interval", selection: $stateBroadcastSecs) {
							Text("Never").tag(0)
							ForEach(UpdateIntervals.allCases) { ui in
								Text(ui.description).tag(ui.rawValue)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						.listRowSeparator(.hidden)
						Text("How often to send detection sensor state to mesh regardless of detection. Default is Never.")
							.font(.callout)
							.foregroundStyle(.gray)
					}
				}
			}
		}
		.scrollDismissesKeyboard(.interactively)
		.disabled(self.bleManager.connectedPeripheral == nil || node?.detectionSensorConfig == nil)

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
			if connectedNode != nil {
				var dsc = ModuleConfig.DetectionSensorConfig()
				dsc.enabled = self.enabled
				dsc.sendBell = self.sendBell
				dsc.name = self.name
				dsc.monitorPin = UInt32(self.monitorPin)
				dsc.detectionTriggerType = TriggerTypes(rawValue: triggerType)!.protoEnumValue()
				dsc.usePullup = self.usePullup
				dsc.minimumBroadcastSecs = UInt32(self.minimumBroadcastSecs)
				dsc.stateBroadcastSecs = UInt32(self.stateBroadcastSecs)
				let adminMessageId = bleManager.saveDetectionSensorModuleConfig(config: dsc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				if adminMessageId > 0 {
					// Should show a saved successfully alert once I know that to be true
					// for now just disable the button after a successful save
					hasChanges = false
					goBack()
				}
			}
		}
		.navigationTitle("detection.sensor.config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onFirstAppear {
			// Need to request a DetectionSensorModuleConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.detectionSensorConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired detection sensor module config requesting via PKI admin")
								_ = bleManager.requestDetectionSensorModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin, empty detection sensor module config")
							_ = bleManager.requestDetectionSensorModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
						}
					}
				}
			}
		}
		.onChange(of: enabled) { _, newEnabled in
			if newEnabled != node?.detectionSensorConfig?.enabled { hasChanges = true }
		}
		.onChange(of: sendBell) { _, newSendBell in
			if newSendBell != node?.detectionSensorConfig?.sendBell { hasChanges = true }
		}
		.onChange(of: triggerType) { _, newTriggerType in
			if newTriggerType != node?.detectionSensorConfig?.triggerType ?? 0 { hasChanges = true }
		}
		.onChange(of: usePullup) { _, newUsePullup in
			if newUsePullup != node?.detectionSensorConfig?.usePullup { hasChanges = true }
		}
		.onChange(of: name) { _, newName in
			if newName != node?.detectionSensorConfig?.name ?? "" { hasChanges = true }
		}
		.onChange(of: monitorPin) { _, newMonitorPin in
			if newMonitorPin != node?.detectionSensorConfig?.monitorPin ?? 0 { hasChanges = true }
		}
		.onChange(of: minimumBroadcastSecs) { _, newMinimumBroadcastSecs in
			if newMinimumBroadcastSecs != node?.detectionSensorConfig?.minimumBroadcastSecs ?? 0 { hasChanges = true }
		}
		.onChange(of: stateBroadcastSecs) { _, newStateBroadcastSecs in
			if newStateBroadcastSecs != node?.detectionSensorConfig?.stateBroadcastSecs ?? 0 { hasChanges = true }
		}
		.onChange(of: detectionNotificationsEnabled) { _, newDetectionNotificationsEnabled in
			UserDefaults.enableDetectionNotifications = newDetectionNotificationsEnabled
		}
	}
	func setDetectionSensorValues() {
		self.enabled = (node?.detectionSensorConfig?.enabled ?? false)
		self.sendBell = (node?.detectionSensorConfig?.sendBell ?? false)
		self.name = (node?.detectionSensorConfig?.name ?? "")
		self.monitorPin = Int(node?.detectionSensorConfig?.monitorPin ?? 0)
		self.usePullup = (node?.detectionSensorConfig?.usePullup ?? false)
		self.triggerType = Int(node?.detectionSensorConfig?.triggerType ?? 0)
		self.minimumBroadcastSecs = Int(node?.detectionSensorConfig?.minimumBroadcastSecs ?? 45)
		self.stateBroadcastSecs = Int(node?.detectionSensorConfig?.stateBroadcastSecs ?? 0)

		self.hasChanges = false
	}
}
