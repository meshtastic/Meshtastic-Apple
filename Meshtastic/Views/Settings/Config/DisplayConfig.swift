//
//  DeviceSettings.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/7/22.
//

import SwiftUI

struct DisplayConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false

	@State var screenOnSeconds = 0
	@State var screenCarouselInterval = 0
	@State var gpsFormat = 0
	@State var compassNorthTop = false
	@State var flipScreen = false
	@State var oledType = 0
	@State var displayMode = 0

	var body: some View {

		Form {
			if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				Text("There has been no response to a request for device metadata over the admin channel for this node.")
					.font(.callout)
					.foregroundColor(.orange)

			} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				// Let users know what is going on if they are using remote admin and don't have the config yet
				if node?.displayConfig == nil {
					Text("Display config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
						.font(.callout)
						.foregroundColor(.orange)
				} else {
					Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
						.font(.title3)
				}
			} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? 0 {
				Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
					.font(.title3)
			} else {
				Text("Please connect to a radio to configure settings.")
					.font(.callout)
					.foregroundColor(.orange)
			}
			Section(header: Text("Device Screen")) {
				Picker("Display Mode", selection: $displayMode ) {
					ForEach(DisplayModes.allCases) { dm in
						Text(dm.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())
				Text("Override automatic OLED screen detection.")
					.font(.caption)

				Toggle(isOn: $compassNorthTop) {

					Label("Always point north", systemImage: "location.north.circle")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Text("The compass heading on the screen outside of the circle will always point north.")
					.font(.caption)

				Toggle(isOn: $flipScreen) {

					Label("Flip Screen", systemImage: "pip.swap")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Text("Flip screen vertically")
					.font(.caption)

				Picker("OLED Type", selection: $oledType ) {
					ForEach(OledTypes.allCases) { ot in
						Text(ot.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())
				Text("Override automatic OLED screen detection.")
					.font(.caption)

			}
			Section(header: Text("Timing & Format")) {
				Picker("Screen on for", selection: $screenOnSeconds ) {
					ForEach(ScreenOnIntervals.allCases) { soi in
						Text(soi.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())
				Text("How long the screen remains on after the user button is pressed or messages are received.")
					.font(.caption)

				Picker("Carousel Interval", selection: $screenCarouselInterval ) {
					ForEach(ScreenCarouselIntervals.allCases) { sci in
						Text(sci.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())
				Text("Automatically toggles to the next page on the screen like a carousel, based the specified interval.")
					.font(.caption)

				Picker("GPS Format", selection: $gpsFormat ) {
					ForEach(GpsFormats.allCases) { lu in
						Text(lu.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())

				Text("The format used to display GPS coordinates on the device screen.")
					.font(.caption)
					.listRowSeparator(.visible)
			}
		}
		.disabled(self.bleManager.connectedPeripheral == nil || node?.displayConfig == nil)

		Button {

			isPresentingSaveConfirm = true

		} label: {

			Label("save", systemImage: "square.and.arrow.down")
		}
		.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding()
		.confirmationDialog(
			"are.you.sure",
			isPresented: $isPresentingSaveConfirm
		) {
			let nodeName = node?.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown")
			let buttonText = String.localizedStringWithFormat(NSLocalizedString("save.config %@", comment: "Save Config for %@"), nodeName)
			Button(buttonText) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil {
					var dc = Config.DisplayConfig()
					dc.gpsFormat = GpsFormats(rawValue: gpsFormat)!.protoEnumValue()
					dc.screenOnSecs = UInt32(screenOnSeconds)
					dc.autoScreenCarouselSecs = UInt32(screenCarouselInterval)
					dc.compassNorthTop = compassNorthTop
					dc.flipScreen = flipScreen
					dc.oled = OledTypes(rawValue: oledType)!.protoEnumValue()
					dc.displaymode = DisplayModes(rawValue: displayMode)!.protoEnumValue()

					let adminMessageId =  bleManager.saveDisplayConfig(config: dc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {

						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
		}
		message: {
			Text("config.save.confirm")
		}
		.navigationTitle("display.config")
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
			self.gpsFormat = Int(node?.displayConfig?.gpsFormat ?? 0)
			self.screenOnSeconds = Int(node?.displayConfig?.screenOnSeconds ?? 0)
			self.screenCarouselInterval = Int(node?.displayConfig?.screenCarouselInterval ?? 0)
			self.compassNorthTop = node?.displayConfig?.compassNorthTop ?? false
			self.flipScreen = node?.displayConfig?.flipScreen ?? false
			self.oledType = Int(node?.displayConfig?.oledType ?? 0)
			self.displayMode = Int(node?.displayConfig?.displayMode ?? 0)
			self.hasChanges = false

			// Need to request a LoRaConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.displayConfig == nil {
				print("empty display config")
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
	}
}
