//
//  PositionConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/11/22.
//

import SwiftUI
import MeshtasticProtobufs
import OSLog

struct PositionFlags: OptionSet {
	let rawValue: Int
	static let Altitude = PositionFlags(rawValue: 1)
	static let AltitudeMsl = PositionFlags(rawValue: 2)
	static let GeoidalSeparation = PositionFlags(rawValue: 4)
	static let Dop = PositionFlags(rawValue: 8)
	static let Hvdop = PositionFlags(rawValue: 16)
	static let Satsinview = PositionFlags(rawValue: 32)
	static let SeqNo = PositionFlags(rawValue: 64)
	static let Timestamp = PositionFlags(rawValue: 128)
	static let Speed = PositionFlags(rawValue: 256)
	static let Heading = PositionFlags(rawValue: 512)
}

struct PositionConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State var hasChanges = false
	@State var hasFlagChanges = false
	@State var smartPositionEnabled = true
	@State var deviceGpsEnabled = true
	@State var gpsMode = 0
	@State var rxGpio = 0
	@State var txGpio = 0
	@State var gpsEnGpio = 0
	@State var fixedPosition = false
	@State var gpsUpdateInterval = 0
	@State var positionBroadcastSeconds = 0
	@State var broadcastSmartMinimumDistance = 0
	@State var broadcastSmartMinimumIntervalSecs = 0
	@State var positionFlags = 811

	/// Position Flags
	/// Altitude value - 1
	@State var includeAltitude = false
	/// Altitude value is MSL - 2
	@State var includeAltitudeMsl = false
	/// Include geoidal separation - 4
	@State var includeGeoidalSeparation = false
	/// Include the DOP value ; PDOP used by default, see below - 8
	@State var includeDop = false
	/// If POS_DOP set, send separate HDOP / VDOP values instead of PDOP - 16
	@State var includeHvdop = false
	/// Include number of "satellites in view" - 32
	@State var includeSatsinview = false
	/// Include a sequence number incremented per packet - 64
	@State var includeSeqNo = false
	/// Include positional timestamp (from GPS solution) - 128
	@State var includeTimestamp = false
	/// Include positional heading - 256
	/// Intended for use with vehicle not walking speeds
	/// walking speeds are likely to be error prone like the compass
	@State var includeSpeed = false
	/// Include positional speed - 512
	/// Intended for use with vehicle not walking speeds
	/// walking speeds are likely to be error prone like the compass
	@State var includeHeading = false
	/// Minimum Version for fixed postion admin messages
	@State var minimumVersion = "2.3.3"
	@State private var supportedVersion = true
	@State private var showingSetFixedAlert = false
	// @State private var showingRemoveFixedAlert = false

	@ViewBuilder
	var positionPacketSection: some View {
		Section(header: Text("Position Packet")) {

			VStack(alignment: .leading) {
				Picker("Broadcast Interval", selection: $positionBroadcastSeconds) {
					ForEach(UpdateIntervals.allCases) { at in
						if at.rawValue >= 300 {
							Text(at.description)
						}
					}
				}
				.pickerStyle(DefaultPickerStyle())
				Text("The maximum interval that can elapse without a node broadcasting a position")
					.foregroundColor(.gray)
					.font(.callout)
			}

			Toggle(isOn: $smartPositionEnabled) {
				Label("Smart Position", systemImage: "brain")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			if smartPositionEnabled {
				VStack(alignment: .leading) {
					Picker("Minimum Interval", selection: $broadcastSmartMinimumIntervalSecs) {
						ForEach(UpdateIntervals.allCases) { at in
							Text(at.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("The fastest that position updates will be sent if the minimum distance has been satisfied")
						.foregroundColor(.gray)
						.font(.callout)
				}
				VStack(alignment: .leading) {
					Picker("Minimum Distance", selection: $broadcastSmartMinimumDistance) {
						ForEach(10..<151) {
							if $0 == 0 {
								Text("unset")
							} else {
								if $0.isMultiple(of: 5) {
									Text("\($0)")
										.tag($0)
								}
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("The minimum distance change in meters to be considered for a smart position broadcast.")
						.foregroundColor(.gray)
						.font(.callout)
				}
			}
		}
	}

	@ViewBuilder
	var deviceGPSSection: some View {
		Section(header: Text("Device GPS")) {
			Picker("", selection: $gpsMode) {
				ForEach(GpsMode.allCases, id: \.self) { at in
					Text(at.description)
						.tag(at.id)

				}
			}
			.pickerStyle(SegmentedPickerStyle())
			.padding(.top, 5)
			.padding(.bottom, 5)
			.disabled(fixedPosition && !(gpsMode == 1))
			if gpsMode == 1 {
				Text("Positions will be provided by your device GPS, if you select disabled or not present you can set a fixed position.")
					.foregroundColor(.gray)
					.font(.callout)
				VStack(alignment: .leading) {
					Picker("Update Interval", selection: $gpsUpdateInterval) {
						ForEach(GpsUpdateIntervals.allCases) { ui in
							Text(ui.description)
						}
					}
					Text("How often should we try to get a GPS position.")
						.foregroundColor(.gray)
						.font(.callout)
				}
			}
			if (gpsMode != 1 && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? -1) || fixedPosition {
				VStack(alignment: .leading) {
					Toggle(isOn: $fixedPosition) {
						Label("Fixed Position", systemImage: "location.square.fill")
						if !(node?.positionConfig?.fixedPosition ?? false) {
							Text("Your current location will be set as the fixed position and broadcast over the mesh on the position interval.")
						} else {

						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
		}
	}

	@ViewBuilder
	var positionFlagsSection: some View {
		Section(header: Text("Position Flags")) {

			Text("Optional fields to include when assembling position messages. the more fields are included, the larger the message will be - leading to longer airtime and a higher risk of packet loss")
				.foregroundColor(.gray)
				.font(.callout)

			Toggle(isOn: $includeAltitude) {
				Label("Altitude", systemImage: "arrow.up")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Toggle(isOn: $includeSatsinview) {
				Label("Number of satellites", systemImage: "skew")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Toggle(isOn: $includeSeqNo) { // 64
				Label("Sequence number", systemImage: "number")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Toggle(isOn: $includeTimestamp) { // 128
				Label("timestamp", systemImage: "clock")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Toggle(isOn: $includeHeading) { // 128
				Label("Vehicle heading", systemImage: "location.circle")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Toggle(isOn: $includeSpeed) { // 128

				Label("Vehicle speed", systemImage: "speedometer")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))
		}
	}

	@ViewBuilder
	var advancedPositionFlagsSection: some View {
		Section(header: Text("Advanced Position Flags")) {

			if includeAltitude {
				Toggle(isOn: $includeAltitudeMsl) {
					Label("Altitude is Mean Sea Level", systemImage: "arrow.up.to.line.compact")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Toggle(isOn: $includeGeoidalSeparation) {
					Label("Altitude Geoidal Separation", systemImage: "globe.americas")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			}

			Toggle(isOn: $includeDop) {
				Text("Dilution of precision (DOP) PDOP used by default")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			if includeDop {
				Toggle(isOn: $includeHvdop) {
					Text("If DOP is set, use HDOP / VDOP values instead of PDOP")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			}
		}
	}

	@ViewBuilder
	var advancedDeviceGPSSection: some View {
		Section(header: Text("Advanced Device GPS")) {
			Picker("GPS Receive GPIO", selection: $rxGpio) {
				ForEach(0..<49) {
					if $0 == 0 {
						Text("unset")
					} else {
						Text("Pin \($0)")
					}
				}
			}
			.pickerStyle(DefaultPickerStyle())
			Picker("GPS Transmit GPIO", selection: $txGpio) {
				ForEach(0..<49) {
					if $0 == 0 {
						Text("unset")
					} else {
						Text("Pin \($0)")
					}
				}
			}
			.pickerStyle(DefaultPickerStyle())
			Picker("GPS EN GPIO", selection: $gpsEnGpio) {
				ForEach(0..<49) {
					if $0 == 0 {
						Text("unset")
					} else {
						Text("Pin \($0)")
					}
				}
			}
			.pickerStyle(DefaultPickerStyle())
			Text("(Re)define PIN_GPS_EN for your board.")
				.font(.caption)
		}
	}

	var saveButton: some View {
		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			if fixedPosition && !supportedVersion {
				_ = bleManager.sendPosition(channel: 0, destNum: node?.num ?? 0, wantResponse: true)
			}
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral!.num, context: context)

			if connectedNode != nil {
				var pc = Config.PositionConfig()
				pc.positionBroadcastSmartEnabled = smartPositionEnabled
				pc.gpsEnabled = gpsMode == 1
				pc.gpsMode = Config.PositionConfig.GpsMode(rawValue: gpsMode) ?? Config.PositionConfig.GpsMode.notPresent
				pc.fixedPosition = fixedPosition
				pc.gpsUpdateInterval = UInt32(gpsUpdateInterval)
				pc.positionBroadcastSecs = UInt32(positionBroadcastSeconds)
				pc.broadcastSmartMinimumIntervalSecs = UInt32(broadcastSmartMinimumIntervalSecs)
				pc.broadcastSmartMinimumDistance = UInt32(broadcastSmartMinimumDistance)
				pc.rxGpio = UInt32(rxGpio)
				pc.txGpio = UInt32(txGpio)
				pc.gpsEnGpio = UInt32(gpsEnGpio)
				var pf: PositionFlags = []
				if includeAltitude { pf.insert(.Altitude) }
				if includeAltitudeMsl { pf.insert(.AltitudeMsl) }
				if includeGeoidalSeparation { pf.insert(.GeoidalSeparation) }
				if includeDop { pf.insert(.Dop) }
				if includeHvdop { pf.insert(.Hvdop) }
				if includeSatsinview { pf.insert(.Satsinview) }
				if includeSeqNo { pf.insert(.SeqNo) }
				if includeTimestamp { pf.insert(.Timestamp) }
				if includeSpeed { pf.insert(.Speed) }
				if includeHeading { pf.insert(.Heading) }
				pc.positionFlags = UInt32(pf.rawValue)
				let adminMessageId =  bleManager.savePositionConfig(config: pc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				if adminMessageId > 0 {
					// Disable the button after a successful save
					hasChanges = false
					goBack()
				}
			}
		}
	}

	var setFixedAlertTitle: String {
		if node?.positionConfig?.fixedPosition == true {
			return "Remove Fixed Position"
		} else {
			return "Set Fixed Position"
		}
	}

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Position", config: \.positionConfig, node: node, onAppear: setPositionValues)
				positionPacketSection
				deviceGPSSection
				positionFlagsSection
				advancedPositionFlagsSection
				if gpsMode == 1 {
					advancedDeviceGPSSection
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.positionConfig == nil)
			.alert(setFixedAlertTitle, isPresented: $showingSetFixedAlert) {
				Button("Cancel", role: .cancel) {
					fixedPosition = !fixedPosition
				}
				if node?.positionConfig?.fixedPosition ?? false {
					Button("Remove", role: .destructive) {
						removeFixedPosition()
					}
				} else {
					Button("Set") {
						setFixedPosition()
					}
				}
			} message: {
				Text(node?.positionConfig?.fixedPosition ?? false ? "This will disable fixed position and remove the currently set position." : "This will send a current position from your phone and enable fixed position.")
			}
			saveButton
		}
		.navigationTitle("position.config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setPositionValues()
			supportedVersion = bleManager.connectedVersion == "0.0.0" ||  self.minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedSame
			// Need to request a PositionConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, node?.positionConfig == nil {
				Logger.mesh.info("empty position config")
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let node, let connectedNode {
					_ = bleManager.requestPositionConfig(
						fromUser: connectedNode.user!,
						toUser: node.user!,
						adminIndex: connectedNode.myInfo?.adminIndex ?? 0
					)
				}
			}
		}
		.onChange(of: fixedPosition) { newFixed in
			if supportedVersion {
				if let positionConfig = node?.positionConfig {
					/// Fixed Position is off to start
					if !positionConfig.fixedPosition && newFixed {
						showingSetFixedAlert = true
					} else if positionConfig.fixedPosition && !newFixed {
						/// Fixed Position is on to start
						showingSetFixedAlert = true
					}
				}
			}
		}
		.onChange(of: gpsMode) { _ in
			handleChanges()
		}
		.onChange(of: rxGpio) { _ in
			handleChanges()
		}
		.onChange(of: txGpio) { _ in
			handleChanges()
		}
		.onChange(of: gpsEnGpio) { _ in
			handleChanges()
		}
		.onChange(of: smartPositionEnabled) { _ in
			handleChanges()
		}
		.onChange(of: positionBroadcastSeconds) { _ in
			handleChanges()
		}
		.onChange(of: broadcastSmartMinimumIntervalSecs) { _ in
			handleChanges()
		}
		.onChange(of: broadcastSmartMinimumDistance) { _ in
			handleChanges()
		}
		.onChange(of: gpsUpdateInterval) { _ in
			handleChanges()
		}
		.onChange(of: positionFlags) { _ in
			handleChanges()
		}
	}

	func handleChanges() {
		guard let positionConfig = node?.positionConfig else { return }
		let pf = PositionFlags(rawValue: self.positionFlags)
		hasChanges = positionConfig.deviceGpsEnabled != deviceGpsEnabled ||
		positionConfig.gpsMode != gpsMode ||
		positionConfig.rxGpio != rxGpio ||
		positionConfig.txGpio != txGpio ||
		positionConfig.gpsEnGpio != gpsEnGpio ||
		positionConfig.smartPositionEnabled != smartPositionEnabled ||
		positionConfig.positionBroadcastSeconds != positionBroadcastSeconds ||
		positionConfig.broadcastSmartMinimumIntervalSecs != broadcastSmartMinimumIntervalSecs ||
		positionConfig.broadcastSmartMinimumDistance != broadcastSmartMinimumDistance ||
		positionConfig.gpsUpdateInterval != gpsUpdateInterval ||
		pf.contains(.Altitude) ||
		pf.contains(.AltitudeMsl) ||
		pf.contains(.Satsinview) ||
		pf.contains(.SeqNo) ||
		pf.contains(.Timestamp) ||
		pf.contains(.Speed) ||
		pf.contains(.Heading) ||
		pf.contains(.GeoidalSeparation) ||
		pf.contains(.Dop) ||
		pf.contains(.Hvdop)
	}

	func setPositionValues() {
		self.smartPositionEnabled = node?.positionConfig?.smartPositionEnabled ?? true
		self.deviceGpsEnabled = node?.positionConfig?.deviceGpsEnabled ?? false
		self.gpsMode = Int(node?.positionConfig?.gpsMode ?? 0)
		if node?.positionConfig?.deviceGpsEnabled ?? false && gpsMode != 1 {
			self.gpsMode = 1
		}
		self.rxGpio = Int(node?.positionConfig?.rxGpio ?? 0)
		self.txGpio = Int(node?.positionConfig?.txGpio ?? 0)
		self.gpsEnGpio = Int(node?.positionConfig?.gpsEnGpio ?? 0)
		self.fixedPosition = node?.positionConfig?.fixedPosition ?? false
		self.gpsUpdateInterval = Int(node?.positionConfig?.gpsUpdateInterval ?? 30)
		self.positionBroadcastSeconds = Int(node?.positionConfig?.positionBroadcastSeconds ?? 900)
		self.broadcastSmartMinimumIntervalSecs = Int(node?.positionConfig?.broadcastSmartMinimumIntervalSecs ?? 30)
		self.broadcastSmartMinimumDistance = Int(node?.positionConfig?.broadcastSmartMinimumDistance ?? 50)
		self.positionFlags = Int(node?.positionConfig?.positionFlags ?? 3)
		let pf = PositionFlags(rawValue: self.positionFlags)
		self.includeAltitude = pf.contains(.Altitude)
		self.includeAltitudeMsl = pf.contains(.AltitudeMsl)
		self.includeGeoidalSeparation = pf.contains(.GeoidalSeparation)
		self.includeDop = pf.contains(.Dop)
		self.includeHvdop = pf.contains(.Hvdop)
		self.includeSatsinview = pf.contains(.Satsinview)
		self.includeSeqNo = pf.contains(.SeqNo)
		self.includeTimestamp = pf.contains(.Timestamp)
		self.includeSpeed = pf.contains(.Speed)
		self.includeHeading = pf.contains(.Heading)
		self.hasChanges = false
	}

	private func setFixedPosition() {
		guard let nodeNum = bleManager.connectedPeripheral?.num,
			  nodeNum > 0 else { return }
		if !bleManager.setFixedPosition(fromUser: node!.user!, channel: 0) {
			Logger.mesh.error("Set Position Failed")
		}
		node?.positionConfig?.fixedPosition = true
		do {
			try context.save()
			Logger.data.info("💾 Updated Position Config with Fixed Position = true")
		} catch {
			context.rollback()
			let nsError = error as NSError
			Logger.data.error("Error Saving Position Config Entity \(nsError)")
		}
	}

	private func removeFixedPosition() {
		guard let nodeNum = bleManager.connectedPeripheral?.num,
			  nodeNum > 0 else { return }
		if !bleManager.removeFixedPosition(fromUser: node!.user!, channel: 0) {
			Logger.mesh.error("Remove Fixed Position Failed")
		}
		let mutablePositions = node?.positions?.mutableCopy() as? NSMutableOrderedSet
		mutablePositions?.removeAllObjects()
		node?.positions = mutablePositions
		node?.positionConfig?.fixedPosition = false
		do {
			try context.save()
			Logger.data.info("💾 Updated Position Config with Fixed Position = false")
		} catch {
			context.rollback()
			let nsError = error as NSError
			Logger.data.error("Error Saving Position Config Entity \(nsError)")
		}
	}
}
