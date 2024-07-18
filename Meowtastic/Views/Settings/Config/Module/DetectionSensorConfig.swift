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
	@State var detectionTriggeredHigh: Bool = true
	@State var usePullup: Bool = false
	@State var minimumBroadcastSecs = 0
	@State var stateBroadcastSecs = 0
	@State var monitorPin = 0

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Detection Sensor", config: \.detectionSensorConfig, node: node)

				Section(header: Text("options")) {
					Toggle(isOn: $enabled) {
						Label("enabled", systemImage: "dot.radiowaves.right")
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
								.onChange(of: name, perform: { _ in

									let totalBytes = name.utf8.count
									// Only mess with the value if it is too big
									if totalBytes > 20 {
										name = String(name.dropLast())
									}
								})
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

						Toggle(isOn: $detectionTriggeredHigh) {
							Label("Detection trigger High", systemImage: "dial.high")
							Text("Whether or not the GPIO pin state detection is triggered on HIGH (1) or LOW (0)")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))

						Toggle(isOn: $usePullup) {
							Label("Uses pullup resistor", systemImage: "arrow.up.to.line")
							Text(" Whether or not use INPUT_PULLUP mode for GPIO pin. Only applicable if the board uses pull-up resistors on the pin")
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
				dsc.detectionTriggeredHigh = self.detectionTriggeredHigh
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
			trailing: ConnectedDevice(ble: bleManager)
		)
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setDetectionSensorValues()
			// Need to request a Detection Sensor Module Config from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.detectionSensorConfig == nil {
				Logger.mesh.info("empty detection sensor module config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestDetectionSensorModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: enabled) { newEnabled in
			if node != nil && node?.detectionSensorConfig != nil {
				if newEnabled != node!.detectionSensorConfig!.enabled { hasChanges = true }
			}
		}
		.onChange(of: sendBell) { newSendBell in
			if node != nil && node?.detectionSensorConfig != nil {
				if newSendBell != node!.detectionSensorConfig!.sendBell { hasChanges = true }
			}
		}
		.onChange(of: detectionTriggeredHigh) { newDetectionTriggeredHigh in
			if node != nil && node?.detectionSensorConfig != nil {
				if newDetectionTriggeredHigh != node!.detectionSensorConfig!.detectionTriggeredHigh { hasChanges = true }
			}
		}
		.onChange(of: usePullup) { newUsePullup in
			if node != nil && node?.detectionSensorConfig != nil {
				if newUsePullup != node!.detectionSensorConfig!.usePullup { hasChanges = true }
			}
		}
		.onChange(of: name) { newName in
			if node != nil && node?.detectionSensorConfig != nil {
				if newName != node!.detectionSensorConfig!.name { hasChanges = true }
			}
		}
		.onChange(of: monitorPin) { newMonitorPin in
			if node != nil && node?.detectionSensorConfig != nil {
				if newMonitorPin != node!.detectionSensorConfig!.monitorPin { hasChanges = true }
			}
		}
		.onChange(of: minimumBroadcastSecs) { newMinimumBroadcastSecs in
			if node != nil && node?.detectionSensorConfig != nil {
				if newMinimumBroadcastSecs != node!.detectionSensorConfig!.minimumBroadcastSecs { hasChanges = true }
			}
		}
		.onChange(of: stateBroadcastSecs) { newStateBroadcastSecs in
			if node != nil && node?.detectionSensorConfig != nil {
				if newStateBroadcastSecs != node!.detectionSensorConfig!.stateBroadcastSecs { hasChanges = true }
			}
		}
		.onChange(of: detectionNotificationsEnabled) { newDetectionNotificationsEnabled in
			UserDefaults.enableDetectionNotifications = newDetectionNotificationsEnabled
		}
	}
	func setDetectionSensorValues() {
		self.enabled = (node?.detectionSensorConfig?.enabled ?? false)
		self.sendBell = (node?.detectionSensorConfig?.sendBell ?? false)
		self.name = (node?.detectionSensorConfig?.name ?? "")
		self.monitorPin = Int(node?.detectionSensorConfig?.monitorPin ?? 0)
		self.usePullup = (node?.detectionSensorConfig?.usePullup ?? false)
		self.detectionTriggeredHigh = (node?.detectionSensorConfig?.detectionTriggeredHigh ?? true)
		self.minimumBroadcastSecs = Int(node?.detectionSensorConfig?.minimumBroadcastSecs ?? 45)
		self.stateBroadcastSecs = Int(node?.detectionSensorConfig?.stateBroadcastSecs ?? 0)

		self.hasChanges = false
	}
}
