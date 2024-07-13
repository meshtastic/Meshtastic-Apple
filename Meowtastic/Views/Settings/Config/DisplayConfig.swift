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
			trailing: ConnectedDevice(ble: bleManager)
		)
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setDisplayValues()

			// Need to request a LoRaConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.displayConfig == nil {
				Logger.mesh.info("empty display config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? 0, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestDisplayConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: screenOnSeconds) { newScreenSecs in
			if node != nil && node!.displayConfig != nil {
				if newScreenSecs != node!.displayConfig!.screenOnSeconds { hasChanges = true }
			}
		}
		.onChange(of: screenCarouselInterval) { newCarouselSecs in
			if node != nil && node!.displayConfig != nil {
				if newCarouselSecs != node!.displayConfig!.screenCarouselInterval { hasChanges = true }
			}
		}
		.onChange(of: compassNorthTop) { newCompassNorthTop in
			if node != nil && node!.displayConfig != nil {
				if newCompassNorthTop != node!.displayConfig!.compassNorthTop { hasChanges = true }
			}
		}
		.onChange(of: wakeOnTapOrMotion) { newWakeOnTapOrMotion in
			if node != nil && node!.displayConfig != nil {
				if newWakeOnTapOrMotion != node!.displayConfig!.wakeOnTapOrMotion { hasChanges = true }
			}
		}
		.onChange(of: gpsFormat) { newGpsFormat in
			if node != nil && node!.displayConfig != nil {
				if newGpsFormat != node!.displayConfig!.gpsFormat { hasChanges = true }
			}
		}
		.onChange(of: flipScreen) { newFlipScreen in
			if node != nil && node!.displayConfig != nil {
				if newFlipScreen != node!.displayConfig!.flipScreen { hasChanges = true }
			}
		}
		.onChange(of: oledType) { newOledType in
			if node != nil && node!.displayConfig != nil {
				if newOledType != node!.displayConfig!.oledType { hasChanges = true }
			}
		}
		.onChange(of: displayMode) { newDisplayMode in
			if node != nil && node!.displayConfig != nil {
				if newDisplayMode != node!.displayConfig!.displayMode { hasChanges = true }
			}
		}
		.onChange(of: units) { newUnits in
			if node != nil && node!.displayConfig != nil {
				if newUnits != node!.displayConfig!.units { hasChanges = true }
			}
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
