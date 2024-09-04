//
//  DeviceSettings.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/7/22.
//

import MeshtasticProtobufs
import OSLog
import SwiftUI

struct DisplayConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State var hasChanges = false
	@State var screenOnSeconds = 0
	@State var screenCarouselInterval = 0
	@State var gpsFormat = 0
	@State var compassNorthTop = false
	@State var wakeOnTapOrMotion = false
	@State var flipScreen = false
	@State var oledType = 0
	@State var displayMode = 0
	@State var units = 0

	var body: some View {
		Form {
			ConfigHeader(title: "Display", config: \.displayConfig, node: node, onAppear: setDisplayValues)

			Section(header: Text("Device Screen")) {
				VStack(alignment: .leading) {
					Picker("Display Mode", selection: $displayMode ) {
						ForEach(DisplayModes.allCases) { dm in
							Text(dm.description)
						}
					}

					Text("Override automatic OLED screen detection.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())
				Toggle(isOn: $compassNorthTop) {
					Label("Always point north", systemImage: "location.north.circle")
					Text("The compass heading on the screen outside of the circle will always point north.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				Toggle(isOn: $wakeOnTapOrMotion) {
					Label("Wake Screen on tap or motion", systemImage: "gyroscope")
					Text("Requires that there be an accelerometer on your device.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				Toggle(isOn: $flipScreen) {
					Label("Flip Screen", systemImage: "pip.swap")
					Text("Flip screen vertically")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				VStack(alignment: .leading) {
					Picker("OLED Type", selection: $oledType ) {
						ForEach(OledTypes.allCases) { ot in
							Text(ot.description)
						}
					}
					Text("Override automatic OLED screen detection.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())
			}
			Section(header: Text("Timing & Format")) {
				VStack(alignment: .leading) {
					Picker("Screen on for", selection: $screenOnSeconds ) {
						ForEach(ScreenOnIntervals.allCases) { soi in
							Text(soi.description)
						}
					}
					Text("How long the screen remains on after the user button is pressed or messages are received.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())

				VStack(alignment: .leading) {
					Picker("Carousel Interval", selection: $screenCarouselInterval ) {
						ForEach(ScreenCarouselIntervals.allCases) { sci in
							Text(sci.description)
						}
					}

					Text("Automatically toggles to the next page on the screen like a carousel, based the specified interval.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())

				VStack(alignment: .leading) {
					Picker("GPS Format", selection: $gpsFormat ) {
						ForEach(GpsFormats.allCases) { lu in
							Text(lu.description)
						}
					}
					Text("The format used to display GPS coordinates on the device screen.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())

				VStack(alignment: .leading) {
					Picker("Display Units", selection: $units ) {
						ForEach(Units.allCases) { un in
							Text(un.description)
						}
					}
					Text("Units displayed on the device screen")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())
			}
		}
		.disabled(self.bleManager.connectedPeripheral == nil || node?.displayConfig == nil)

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
			if connectedNode != nil {
				var dc = Config.DisplayConfig()
				dc.gpsFormat = GpsFormats(rawValue: gpsFormat)!.protoEnumValue()
				dc.screenOnSecs = UInt32(screenOnSeconds)
				dc.autoScreenCarouselSecs = UInt32(screenCarouselInterval)
				dc.compassNorthTop = compassNorthTop
				dc.wakeOnTapOrMotion = wakeOnTapOrMotion
				dc.flipScreen = flipScreen
				dc.oled = OledTypes(rawValue: oledType)!.protoEnumValue()
				dc.displaymode = DisplayModes(rawValue: displayMode)!.protoEnumValue()
				dc.units = Units(rawValue: units)!.protoEnumValue()

				let adminMessageId =  bleManager.saveDisplayConfig(config: dc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				if adminMessageId > 0 {

					// Should show a saved successfully alert once I know that to be true
					// for now just disable the button after a successful save
					hasChanges = false
					goBack()
				}
			}
		}

		.navigationTitle("display.config")
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
			// Need to request a DisplayConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				Logger.mesh.info("empty display config")
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if UserDefaults.enableAdministration {
						/// 2.5 Administration with session passkey
						let expiration = node.sessionExpiration ?? Date()
						if expiration < Date() || node.displayConfig == nil {
							_ = bleManager.requestDisplayConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
						}
					} else {
						/// Legacy Administration
						_ = bleManager.requestDisplayConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
					}
				}
			}
		}
		.onChange(of: screenOnSeconds) { newScreenSecs in
			if newScreenSecs != node?.displayConfig?.screenOnSeconds ?? -1 { hasChanges = true }
		}
		.onChange(of: screenCarouselInterval) { newCarouselSecs in
			if newCarouselSecs != node?.displayConfig?.screenCarouselInterval ?? -1 { hasChanges = true }
		}
		.onChange(of: compassNorthTop) {
			if $0 != node?.displayConfig?.compassNorthTop { hasChanges = true }
		}
		.onChange(of: wakeOnTapOrMotion) {
			if $0 != node?.displayConfig?.wakeOnTapOrMotion { hasChanges = true }
		}
		.onChange(of: gpsFormat) { newGpsFormat in
			if newGpsFormat != node?.displayConfig?.gpsFormat ?? -1 { hasChanges = true }
		}
		.onChange(of: flipScreen) {
			if $0 != node?.displayConfig?.flipScreen { hasChanges = true }
		}
		.onChange(of: oledType) { newOledType in
			if newOledType != node?.displayConfig?.oledType ?? -1 { hasChanges = true }
		}
		.onChange(of: displayMode) { newDisplayMode in
			if newDisplayMode != node?.displayConfig?.displayMode ?? -1 { hasChanges = true }
		}
		.onChange(of: units) { newUnits in
			if newUnits != node?.displayConfig?.units ?? -1 { hasChanges = true }
		}
	}
	func setDisplayValues() {
			self.gpsFormat = Int(node?.displayConfig?.gpsFormat ?? 0)
			self.screenOnSeconds = Int(node?.displayConfig?.screenOnSeconds ?? 0)
			self.screenCarouselInterval = Int(node?.displayConfig?.screenCarouselInterval ?? 0)
			self.compassNorthTop = node?.displayConfig?.compassNorthTop ?? false
			self.wakeOnTapOrMotion = node?.displayConfig?.wakeOnTapOrMotion ?? false
			self.flipScreen = node?.displayConfig?.flipScreen ?? false
			self.oledType = Int(node?.displayConfig?.oledType ?? 0)
			self.displayMode = Int(node?.displayConfig?.displayMode ?? 0)
			self.units = Int(node?.displayConfig?.units ?? 0)
			self.hasChanges = false
	}
}
