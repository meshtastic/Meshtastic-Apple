//
//  LoRaConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) by Garth Vander Houwen 6/11/22.
//

import SwiftUI
import SwiftData
import MeshtasticProtobufs
import OSLog

struct LoRaConfig: View {

	enum Field: Hashable {
		case channelNum
		case frequencyOverride
	}

	let formatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.groupingSeparator = ""
		return formatter
	}()

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	@FocusState var focusedField: Field?

	let node: NodeInfoEntity?

	private var selectedModemPreset: ModemPresets {
		ModemPresets(rawValue: modemPreset) ?? .longFast
	}

	private var normalizedCodingRate: Int {
		CodingRates.normalized(codingRate, usePreset: usePreset, modemPreset: selectedModemPreset)
	}

	private var defaultCodingRate: Int {
		selectedModemPreset.defaultCodingRate
	}

	private var canOverridePresetCodingRate: Bool {
		defaultCodingRate < CodingRates.validRange.upperBound
	}

	private var usePresetCodingRate: Binding<Bool> {
		Binding(
			get: { normalizedCodingRate == 0 },
			set: { useDefault in
				if useDefault || !canOverridePresetCodingRate {
					codingRate = 0
				} else {
					codingRate = defaultCodingRate + 1
				}
			}
		)
	}

	private var presetCodingRateSliderValue: Binding<Double> {
		Binding(
			get: {
				let firstOverride = defaultCodingRate + 1
				return Double(max(normalizedCodingRate, firstOverride))
			},
			set: { newValue in
				codingRate = Int(newValue.rounded())
			}
		)
	}

	private var customCodingRateSliderValue: Binding<Double> {
		Binding(
			get: { Double(normalizedCodingRate) },
			set: { newValue in
				codingRate = CodingRates.normalized(
					Int(newValue.rounded()),
					usePreset: false,
					modemPreset: selectedModemPreset
				)
			}
		)
	}

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
	@State var okToMqtt = false

	let floatFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.allowsFloats = true
		formatter.maximumFractionDigits = 4
		return formatter
	}()

	/// Whether the connected radio runs firmware new enough for the 2.8 LoRa
	/// region/preset rework. Gates the new ham regions and narrow/tiny presets so
	/// they can't be set on 2.7.x-and-earlier devices.
	private var supports2_8: Bool {
		accessoryManager.checkIsVersionSupported(forVersion: "2.8.0")
	}

	/// The compatibility info the firmware advertised for the currently selected
	/// region, if any. Absent ⇒ no constraint (spec §5.1 / §5.2). Only consulted
	/// when the connected radio supports the 2.8 rework, so a map left over from a
	/// previously-connected 2.8 device is ignored on a 2.7.x radio.
	private var regionPresetInfo: RegionPresetInfo? {
		guard supports2_8, let code = RegionCodes(rawValue: region)?.protoEnumValue() else { return nil }
		return accessoryManager.loRaRegionPresets[code]
	}

	/// Modem presets offered in the picker: the firmware-gated set, further
	/// constrained to the selected region's legal list when the firmware provided
	/// one. Never empty (spec §6 — never show an empty picker).
	private var availablePresets: [ModemPresets] {
		let base = ModemPresets.selectable(supports2_8: supports2_8)
		var presets = base
		if let info = regionPresetInfo, !info.presets.isEmpty {
			let constrained = base.filter { info.presets.contains($0.protoEnumValue()) }
			if !constrained.isEmpty { presets = constrained }
		}
		// Keep a currently-configured but deprecated preset (e.g. Long Slow on an existing
		// radio) visible so the picker doesn't render a blank selection.
		if let current = ModemPresets(rawValue: modemPreset), current.isDeprecated, !presets.contains(current) {
			presets.append(current)
		}
		return presets
	}

	private var availableBandwidths: [Bandwidths] {
		Bandwidths.selectable(
			region: RegionCodes(rawValue: region),
			pioEnv: node?.myInfo?.pioEnv
		)
	}

	private var customBandwidthValidationIssue: Bandwidths.ValidationIssue? {
		guard !usePreset else { return nil }
		return Bandwidths.validationIssue(
			for: bandwidth,
			region: RegionCodes(rawValue: region),
			pioEnv: node?.myInfo?.pioEnv
		)
	}

	private var bandwidthSelection: Binding<Int> {
		Binding(
			get: {
				Bandwidths.pickerValue(
					forStoredValue: bandwidth,
					region: RegionCodes(rawValue: region)
				)
			},
			set: { bandwidth = $0 }
		)
	}

	var body: some View {
		// The fourteen .onChange closures each carry a mixed-optional comparison
		// (`newX != node?.loRaConfig?.x ?? -1`); solved together with the inlined Form
		// they formed a single ~10s type-check expression (build-snapshots' budget
		// blowups). Rooting the chain at an opaque property splits the solve.
		trackedForm
		.onChange(of: codingRate) { _, newCodingRate in
			let normalizedNewCodingRate = CodingRates.normalized(newCodingRate, usePreset: usePreset, modemPreset: selectedModemPreset)
			if normalizedNewCodingRate != newCodingRate {
				codingRate = normalizedNewCodingRate
			}
			if normalizedNewCodingRate != node?.loRaConfig?.codingRate ?? -1 { hasChanges = true }
		}
		.onChange(of: spreadFactor) { _, newSpreadFactor in
			if newSpreadFactor != node?.loRaConfig?.spreadFactor ?? -1 { hasChanges = true }
		}
		.onChange(of: rxBoostedGain) { _, newRxBoostedGain in
			if newRxBoostedGain != node?.loRaConfig?.sx126xRxBoostedGain { hasChanges = true }
		}
		.onChange(of: overrideFrequency) { _, newOverrideFrequency in
			if newOverrideFrequency != node?.loRaConfig?.overrideFrequency { hasChanges = true }
		}
		.onChange(of: txPower) { _, newTxPower in
			if Int32(newTxPower) != node?.loRaConfig?.txPower { hasChanges = true }
		}
		.onChange(of: txEnabled) { _, newTxEnabled in
			if newTxEnabled != node?.loRaConfig?.txEnabled { hasChanges = true }
		}
		.onChange(of: ignoreMqtt) { _, newIgnoreMqtt in
			if newIgnoreMqtt != node?.loRaConfig?.ignoreMqtt { hasChanges = true }
		}
		.onChange(of: okToMqtt) { _, newOkToMqtt in
			if newOkToMqtt != node?.loRaConfig?.okToMqtt { hasChanges = true }
		}
	}

	/// First half of the change-tracking chain — all the .onChange calls chained in one
	/// expression were still a multi-second type-check after the section/save splits;
	/// halving the chain keeps each solve small.
	private var trackedForm: some View {
		loRaForm
		.onChange(of: region) { _, newRegion in
			if newRegion != node?.loRaConfig?.regionCode ?? -1 { hasChanges = true }
			applyRegionPresetDefault(forRegion: newRegion)
		}
		.onChange(of: accessoryManager.loRaRegionPresets) { _, _ in
			applyRegionPresetDefault(forRegion: region)
		}
		.onChange(of: usePreset) { _, newPreset in
			codingRate = CodingRates.normalized(codingRate, usePreset: newPreset, modemPreset: selectedModemPreset)
			if newPreset != node?.loRaConfig?.usePreset { hasChanges = true }
		}
		.onChange(of: modemPreset) { _, newModemPreset in
			codingRate = CodingRates.normalized(codingRate, usePreset: usePreset, modemPreset: ModemPresets(rawValue: newModemPreset) ?? .longFast)
			if newModemPreset != node?.loRaConfig?.modemPreset ?? -1 { hasChanges = true }
		}
		.onChange(of: hopLimit) { _, newHopLimit in
			if newHopLimit != node?.loRaConfig?.hopLimit ?? -1 { hasChanges = true }
		}
		.onChange(of: channelNum) { _, newChannelNum in
			if newChannelNum != node?.loRaConfig?.channelNum ?? -1 { hasChanges = true }
		}
		.onChange(of: bandwidth) { _, newBandwidth in
			if newBandwidth != node?.loRaConfig?.bandwidth ?? -1 { hasChanges = true }
		}
	}

	/// See `body` — the Form and its chrome, split out for type-check time.
	private var loRaForm: some View {
		Form {
			ConfigHeader(title: "LoRa", config: \.loRaConfig, node: node, onAppear: setLoRaValues)

			optionsSection

			advancedSection
		}
		.scrollDismissesKeyboard(.immediately)
		.disabled(!accessoryManager.isConnected || node?.loRaConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					saveLoRaConfig()
				}
				.disabled(customBandwidthValidationIssue != nil)
			}
		}
		.navigationTitle("LoRa Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.loRaConfig == nil },
				request: accessoryManager.requestLoRaConfig
			)
		}
	}

	/// The save routine, extracted from the `SaveConfigButton` trailing closure — same
	/// type-check-time treatment as SecurityConfig (body's chained expression measured ~10s
	/// with -warn-long-expression-type-checking before extraction).
	private func saveLoRaConfig() {
		guard customBandwidthValidationIssue == nil else { return }
		performConfigSave(
			node: node,
			context: context,
			accessoryManager: accessoryManager,
			hasChanges: $hasChanges,
			dismiss: goBack
		) { fromUser, toUser in
			var lc = Config.LoRaConfig()
			lc.hopLimit = UInt32(hopLimit)
			lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
			lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
			lc.usePreset = usePreset
			lc.txEnabled = txEnabled
			lc.txPower = Int32(txPower)
			lc.channelNum = UInt32(channelNum)
			lc.bandwidth = UInt32(bandwidth)
			lc.codingRate = UInt32(normalizedCodingRate)
			lc.spreadFactor = UInt32(spreadFactor)
			lc.sx126XRxBoostedGain = rxBoostedGain
			lc.overrideFrequency = overrideFrequency
			lc.ignoreMqtt = ignoreMqtt
			lc.configOkToMqtt = okToMqtt
			if let deviceNum = accessoryManager.activeDeviceNum,
			   let connectedNode = getNodeInfo(id: deviceNum, context: context),
			   connectedNode.num == node?.user?.num ?? 0 {
				UserDefaults.modemPreset = modemPreset
			}
			_ = try await accessoryManager.saveLoRaConfig(config: lc, fromUser: fromUser, toUser: toUser)
		}
	}

	/// Extracted from `body`: the inlined Form was a single ~10s type-check expression on
	/// dev hardware (measured with -warn-long-expression-type-checking) and blew the budget
	/// outright on CI's runners (build-snapshots: "unable to type-check in reasonable time").
	private var optionsSection: some View {
		Section(header: Text("Options")) {

			VStack(alignment: .leading) {
				Picker("Region", selection: $region ) {
					// 2.8-only regions (ham/amateur bands, EU SRD/narrow) are
					// hidden when the connected radio runs firmware older than
					// 2.8, which has no band table for them.
					ForEach(RegionCodes.selectable(supports2_8: supports2_8)) { r in
						Text(r.description)
					}
				}
				Text("The region where you will be using your radios.")
					.foregroundColor(.gray)
					.font(.callout)
			}

			if let info = regionPresetInfo, info.licensedOnly {
				let licensed = node?.user?.isLicensed ?? false
				HStack(alignment: .top, spacing: 8) {
					Image(systemName: licensed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
						.foregroundColor(licensed ? .green : .orange)
						// Decorative status glyph; the adjacent "Licensed band" title and
						// description already convey licensed/unlicensed state to VoiceOver.
						.accessibilityHidden(true)
					VStack(alignment: .leading, spacing: 2) {
						Text("Licensed band")
							.font(.callout).bold()
						Text(licensed
							 ? "This region is restricted to licensed amateur radio operators. Your operator profile is marked as licensed.".localized
							 : "This region is restricted to licensed amateur radio operators. Enable “Licensed Operator” and set your call sign in User Config before transmitting.".localized)
							.foregroundColor(.gray)
							.font(.caption)
					}
				}
			}

			Toggle(isOn: $usePreset) {
				Label("Use Preset", systemImage: "list.bullet.rectangle")
			}

			if usePreset {
				VStack(alignment: .leading) {
					Picker("Presets", selection: $modemPreset ) {
						// Constrained to the selected region's legal presets when
						// the firmware advertises a region→preset map (2.8+), and
						// to the firmware-gated set otherwise.
						ForEach(availablePresets) { m in
							Text(m.description)
						}
					}
					.fixedSize()
					Text("Available modem presets, default is Long Fast.")
						.foregroundColor(.gray)
						.font(.callout)
					// Long Fast stays selectable in the US, but its bandwidth is not
					// US-compliant on 2.8 — warn instead of blocking.
					if supports2_8, region == RegionCodes.us.rawValue, modemPreset == ModemPresets.longFast.rawValue {
						Label {
							Text("Long Fast's bandwidth is not compliant in the US. Long Turbo is the recommended preset.")
								.foregroundColor(.gray)
								.font(.caption)
						} icon: {
							Image(systemName: "exclamationmark.triangle.fill")
								.foregroundColor(.orange)
						}
					}
				}
			}
		}
	}

	/// See `optionsSection` — split out of `body` for type-check time.
	private var advancedSection: some View {
		Section(header: Text("Advanced")) {

			Toggle(isOn: $ignoreMqtt) {
				Label("Ignore MQTT", systemImage: "server.rack")
			}
			Toggle(isOn: $okToMqtt) {
				Label("Ok to MQTT", systemImage: "network")
			}

			Toggle(isOn: $txEnabled) {
				Label("Transmit Enabled", systemImage: "waveform.path")
			}

			if !usePreset {
				CustomBandwidthPicker(
					selection: bandwidthSelection,
					options: availableBandwidths,
					region: RegionCodes(rawValue: region),
					validationIssue: customBandwidthValidationIssue
				)
				HStack {
					Picker("Spread Factor", selection: $spreadFactor) {
						ForEach(7..<13) {
							Text("\($0)")
								.tag($0 == 12 ? 0 : $0)
						}
					}
				}
			}

			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Coding Rate")
					Spacer()
					Text(CodingRates.description(for: normalizedCodingRate, modemPreset: selectedModemPreset))
						.foregroundColor(.secondary)
				}
				if usePreset {
					Toggle("Follow Preset Coding Rate", isOn: usePresetCodingRate)
					if !canOverridePresetCodingRate {
						Text("This preset already uses 4/\(defaultCodingRate), the highest redundancy available.")
							.foregroundColor(.gray)
							.font(.callout)
					} else if normalizedCodingRate == 0 {
						Text("Uses \(selectedModemPreset.description)'s 4/\(defaultCodingRate) coding rate. Turn this off only when nearby nodes use the same preset and you want extra error correction on noisy links.")
							.foregroundColor(.gray)
							.font(.callout)
					} else {
						Slider(
							value: presetCodingRateSliderValue,
							in: Double(defaultCodingRate + 1)...Double(CodingRates.validRange.upperBound),
							step: 1
						) {
							Text("Coding Rate")
						} minimumValueLabel: {
							Text("4/\(defaultCodingRate + 1)")
						} maximumValueLabel: {
							Text("4/\(CodingRates.validRange.upperBound)")
						}
						Text("Uses 4/\(normalizedCodingRate) while keeping the \(selectedModemPreset.description) bandwidth and spread factor. Higher values add error correction, but each packet uses more airtime and has less throughput.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				} else {
					Slider(
						value: customCodingRateSliderValue,
						in: Double(CodingRates.validRange.lowerBound)...Double(CodingRates.validRange.upperBound),
						step: 1
					) {
						Text("Coding Rate")
					} minimumValueLabel: {
						Text("4/\(CodingRates.validRange.lowerBound)")
					} maximumValueLabel: {
						Text("4/\(CodingRates.validRange.upperBound)")
					}
					Text("Coding rate controls error-correction redundancy. Higher values can help noisy links, but reduce throughput and increase airtime. Keep 4/5 unless your channel plan calls for a different value.")
						.foregroundColor(.gray)
						.font(.callout)
				}
			}

			VStack(alignment: .leading) {
				Picker("Number of hops", selection: $hopLimit) {
					ForEach(0..<8) {
						Text("\($0)")
							.tag($0)
					}
				}
				Text("Sets the maximum number of hops, default is 3. Increasing hops also increases congestion and should be used carefully. 0 hop broadcast messages will not get ACKs.")
					.foregroundColor(.gray)
					.font(.callout)
			}

			VStack(alignment: .leading) {
				HStack {
					Text("Frequency Slot")
						.fixedSize()
					TextField("Frequency Slot", value: $channelNum, formatter: formatter)
						.keyboardType(.numberPad)
						.focused($focusedField, equals: .channelNum)
						.disabled(overrideFrequency > 0.0)
				}
				Text("Your node’s operating frequency is calculated based on the region, modem preset, and this field. When 0, the slot is automatically calculated based on the primary channel name.")
					.foregroundColor(.gray)
					.font(.callout)
			}

			Toggle(isOn: $rxBoostedGain) {
				Label("RX Boosted Gain", systemImage: "waveform.badge.plus")
			}

			HStack {
				Label("Frequency Override", systemImage: "waveform.path.ecg")
				Spacer()
				TextField("Frequency Override", value: $overrideFrequency, formatter: floatFormatter)
					.keyboardType(.decimalPad)
					.focused($focusedField, equals: .frequencyOverride)
			}

			HStack {
				Image(systemName: "antenna.radiowaves.left.and.right")
					.foregroundColor(.accentColor)
					// Decorative icon; the Stepper carries the label for VoiceOver.
					.accessibilityHidden(true)
				Stepper(txPower == 0 ? "Max Transmit Power" : "\(txPower)dBm Transmit Power", value: $txPower, in: 0...30, step: 1)
					.padding(5)
			}
		}
	}
	/// When the user switches region, pre-select the appropriate preset: a
	/// factory-flashed node defaults to Long Turbo for US on 2.8 firmware, and
	/// otherwise an illegal current preset falls back to the region's advertised
	/// default (spec §5.3 / §6). See `ModemPresets.presetToSelect` for the rules.
	/// A nil result keeps the current selection.
	private func applyRegionPresetDefault(forRegion newRegion: Int) {
		guard let code = RegionCodes(rawValue: newRegion)?.protoEnumValue() else { return }
		let factoryFresh = (node?.loRaConfig?.regionCode ?? 0) == RegionCodes.unset.rawValue
		if let preset = ModemPresets.presetToSelect(
			forRegion: code,
			factoryFresh: factoryFresh,
			supports2_8: supports2_8,
			usePreset: usePreset,
			regionInfo: accessoryManager.loRaRegionPresets[code],
			currentPreset: ModemPresets(rawValue: modemPreset)
		) {
			modemPreset = preset.rawValue
		}
	}

	func setLoRaValues() {
		if node?.loRaConfig?.modemPreset ?? 0 == 2 {
			node?.loRaConfig?.modemPreset = 0
		}
		self.hopLimit = Int(node?.loRaConfig?.hopLimit ?? 3)
		self.region = Int(node?.loRaConfig?.regionCode ?? 0)
		self.usePreset = node?.loRaConfig?.usePreset ?? true
		self.modemPreset = Int(node?.loRaConfig?.modemPreset ?? 0)
		self.txEnabled = node?.loRaConfig?.txEnabled ?? true
		self.txPower = Int(node?.loRaConfig?.txPower ?? 0)
		self.channelNum = Int(node?.loRaConfig?.channelNum ?? 0)
		self.bandwidth = Int(node?.loRaConfig?.bandwidth ?? 0)
		let loadedCodingRate = Int(node?.loRaConfig?.codingRate ?? 0)
		self.codingRate = CodingRates.normalized(
			loadedCodingRate,
			usePreset: self.usePreset,
			modemPreset: ModemPresets(rawValue: self.modemPreset) ?? .longFast
		)
		self.spreadFactor = Int(node?.loRaConfig?.spreadFactor ?? 0)
		self.rxBoostedGain = node?.loRaConfig?.sx126xRxBoostedGain ?? false
		self.overrideFrequency = node?.loRaConfig?.overrideFrequency ?? 0.0
		self.ignoreMqtt = node?.loRaConfig?.ignoreMqtt ?? false
		self.okToMqtt = node?.loRaConfig?.okToMqtt ?? false
		self.hasChanges = false
	}
}

private struct CustomBandwidthPicker: View {
	@Binding var selection: Int
	let options: [Bandwidths]
	let region: RegionCodes?
	let validationIssue: Bandwidths.ValidationIssue?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("Bandwidth", selection: $selection) {
				if validationIssue == .unsupported {
					Text("Unsupported (\(Bandwidths.description(forPickerValue: selection, region: region)))")
						.tag(selection)
				}
				if region == .lora24 {
					Text(Bandwidths.description(forPickerValue: 0, region: region).localized)
						.tag(0)
				}
				ForEach(options) { bandwidth in
					Text(bandwidth.description)
						.tag(bandwidth.pickerValue)
				}
			}
			if let validationIssue {
				Label {
					if validationIssue == .unsupported {
						Text("This bandwidth is not supported by the connected radio in the selected region. Choose a supported value before saving.".localized)
					}
				} icon: {
					Image(systemName: "exclamationmark.triangle.fill")
				}
				.foregroundStyle(.orange)
				.font(.callout)
			}
		}
	}
}

#Preview {
	LoRaConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
