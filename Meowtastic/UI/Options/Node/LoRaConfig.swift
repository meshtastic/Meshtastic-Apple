import CoreData
import FirebaseAnalytics
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct LoRaConfig: View {
	enum Field: Hashable {
		case channelNum
		case frequencyOverride
	}

	private let formatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.groupingSeparator = ""
		return formatter
	}()

	var node: NodeInfoEntity?

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@EnvironmentObject
	private var nodeConfig: NodeConfig
	@Environment(\.dismiss)
	private var goBack
	@FocusState
	private var focusedField: Field?

	@State var hasChanges = false
	@State var region: Int = 0
	@State var modemPreset = 0
	@State var hopLimit = 3
	@State var txPower = 0
	@State var txEnabled = true
	@State var usePreset = true
	@State var channelNum = 0
	@State var bandwidth = 0
	@State var spreadFactor = 0
	@State var codingRate = 0
	@State var rxBoostedGain = false
	@State var overrideFrequency: Float = 0.0
	@State var ignoreMqtt = false

	let floatFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		return formatter
	}()

	@ViewBuilder
	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "LoRa", config: \.loRaConfig, node: node)

				sectionOptions
				sectionAdvanced
			}
			.disabled(bleManager.deviceConnected == nil || node?.loRaConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				if
					let node,
					let connectedPeripheral = bleManager.deviceConnected,
					let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				{
					var lc = Config.LoRaConfig()
					lc.hopLimit = UInt32(hopLimit)
					lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
					lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
					lc.usePreset = usePreset
					lc.txEnabled = txEnabled
					lc.txPower = Int32(txPower)
					lc.channelNum = UInt32(channelNum)
					lc.bandwidth = UInt32(bandwidth)
					lc.codingRate = UInt32(codingRate)
					lc.spreadFactor = UInt32(spreadFactor)
					lc.sx126XRxBoostedGain = rxBoostedGain
					lc.overrideFrequency = overrideFrequency
					lc.ignoreMqtt = ignoreMqtt

					if connectedNode.num == node.user?.num ?? 0 {
						UserDefaults.modemPreset = modemPreset
					}

					let adminMessageId = nodeConfig.saveLoRaConfig(
						config: lc,
						fromUser: connectedNode.user!,
						toUser: node.user!,
						adminIndex: connectedNode.myInfo?.adminIndex ?? 0
					)

					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
		}
		.navigationTitle("LoRa Config")
		.navigationBarItems(
			trailing: ConnectedDevice()
		)
		.onAppear {
			Analytics.logEvent(AnalyticEvents.optionsLoRa.id, parameters: [:])

			setLoRaValues()

			// Need to request a LoRaConfig from the remote node before allowing changes
			if node?.loRaConfig == nil {
				Logger.mesh.info("Empty LoRa config")
			}
			else if
				let node,
				let connectedPeripheral = bleManager.deviceConnected,
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
			{
				nodeConfig.requestLoRaConfig(
					fromUser: connectedNode.user!,
					toUser: node.user!,
					adminIndex: connectedNode.myInfo?.adminIndex ?? 0
				)
			}
		}
		.onChange(of: region) {
			hasChanges = true
		}
		.onChange(of: usePreset) {
			hasChanges = true
		}
		.onChange(of: modemPreset) {
			hasChanges = true
		}
		.onChange(of: hopLimit) {
			hasChanges = true
		}
		.onChange(of: channelNum) {
			hasChanges = true
		}
		.onChange(of: bandwidth) {
			hasChanges = true
		}
		.onChange(of: codingRate) {
			hasChanges = true
		}
		.onChange(of: spreadFactor) {
			hasChanges = true
		}
		.onChange(of: rxBoostedGain) {
			hasChanges = true
		}
		.onChange(of: overrideFrequency) {
			hasChanges = true
		}
		.onChange(of: txPower) {
			hasChanges = true
		}
		.onChange(of: txEnabled) {
			hasChanges = true
		}
		.onChange(of: ignoreMqtt) {
			hasChanges = true
		}
	}

	@ViewBuilder
	private var sectionOptions: some View {
		Section(header: Text("Options")) {
			VStack(alignment: .leading) {
				Picker("Region", selection: $region ) {
					ForEach(RegionCodes.allCases) { region in
						Text(region.description)
					}
				}
				.fixedSize()

				Text("The region where you will be using your radios.")
					.foregroundColor(.gray)
					.font(.callout)
			}
			.pickerStyle(DefaultPickerStyle())

			Toggle(isOn: $usePreset) {
				Label("Use Preset", systemImage: "list.bullet.rectangle")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			if usePreset {
				VStack(alignment: .leading) {
					Picker("Presets", selection: $modemPreset ) {
						ForEach(ModemPresets.allCases) { m in
							Text(m.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.fixedSize()

					Text("Available modem presets, default is Long Fast.")
						.foregroundColor(.gray)
						.font(.callout)
				}
			}
		}
	}

	@ViewBuilder
	private var sectionAdvanced: some View {
		Section(header: Text("Advanced")) {
			Toggle(isOn: $ignoreMqtt) {
				Label("Ignore MQTT", systemImage: "server.rack")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Toggle(isOn: $txEnabled) {
				Label("Transmit Enabled", systemImage: "waveform.path")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			if !usePreset {
				HStack {
					Picker("Bandwidth", selection: $bandwidth) {
						ForEach(Bandwidths.allCases) { bw in
							Text(bw.description)
								.tag(bw.rawValue == 250 ? 0 : bw.rawValue)
						}
					}
				}

				HStack {
					Picker("Spread Factor", selection: $spreadFactor) {
						ForEach(7..<13) {
							Text("\($0)")
								.tag($0 == 12 ? 0 : $0)
						}
					}
				}

				HStack {
					Picker("Coding Rate", selection: $codingRate) {
						ForEach(5..<9) {
							Text("\($0)")
								.tag($0 == 8 ? 0 : $0)
						}
					}
				}
			}

			VStack(alignment: .leading) {
				Picker("Number of hops", selection: $hopLimit) {
					ForEach(0..<8) {
						Text("\($0)")
							.tag($0)
					}
				}

				Text("Sets the maximum number of hops, default is 3. Increasing hops also increases congestion and should be used carefully. O hop broadcast messages will not get ACKs.")
					.foregroundColor(.gray)
					.font(.callout)
			}
			.pickerStyle(DefaultPickerStyle())

			VStack(alignment: .leading) {
				HStack {
					Text("Frequency Slot")
						.fixedSize()

					TextField("Frequency Slot", value: $channelNum, formatter: formatter)
						.toolbar {
							ToolbarItemGroup(placement: .keyboard) {
								Button("dismiss.keyboard") {
									focusedField = nil
								}
								.font(.subheadline)
							}
						}
						.keyboardType(.decimalPad)
						.scrollDismissesKeyboard(.immediately)
						.focused($focusedField, equals: .channelNum)
						.disabled(overrideFrequency > 0.0)
				}

				Text("This determines the actual frequency you are transmitting on in the band. If set to 0 this value will be calculated automatically based on the primary channel name.")
					.foregroundColor(.gray)
					.font(.callout)
			}

			Toggle(isOn: $rxBoostedGain) {
				Label("RX Boosted Gain", systemImage: "waveform.badge.plus")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			HStack {
				Label("Frequency Override", systemImage: "waveform.path.ecg")
				Spacer()
				TextField("Frequency Override", value: $overrideFrequency, formatter: floatFormatter)
					.keyboardType(.decimalPad)
					.scrollDismissesKeyboard(.immediately)
					.focused($focusedField, equals: .frequencyOverride)
			}

			HStack {
				Image(systemName: "antenna.radiowaves.left.and.right")
					.foregroundColor(.accentColor)

				Stepper("\(txPower)dBm Transmit Power", value: $txPower, in: 1...30, step: 1)
					.padding(5)
			}
		}
	}

	private func setLoRaValues() {
		if let config = node?.loRaConfig {
			hopLimit = Int(config.hopLimit)
			region = Int(config.regionCode)
			usePreset = config.usePreset
			modemPreset = Int(config.modemPreset)
			txEnabled = config.txEnabled
			txPower = Int(config.txPower)
			channelNum = Int(config.channelNum)
			bandwidth = Int(config.bandwidth)
			codingRate = Int(config.codingRate)
			spreadFactor = Int(config.spreadFactor)
			rxBoostedGain = config.sx126xRxBoostedGain
			overrideFrequency = config.overrideFrequency
			ignoreMqtt = config.ignoreMqtt
		}
		else {
			hopLimit = 3
			region = 0
			usePreset = true
			modemPreset = 0
			txEnabled = true
			txPower = 0
			channelNum = 0
			bandwidth = 0
			codingRate = 0
			spreadFactor = 0
			rxBoostedGain = false
			overrideFrequency = 0.0
			ignoreMqtt = false
		}

		hasChanges = false
	}
}
