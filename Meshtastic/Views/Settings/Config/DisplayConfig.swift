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
	
	var body: some View {
		
		Form {
			Section(header: Text("Device Screen")) {
				
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
			Section(header: Text("Format")) {
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
		.disabled(bleManager.connectedPeripheral == nil)
		
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
			let nodeName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : NSLocalizedString("unknown", comment: "Unknown")
			let buttonText = String.localizedStringWithFormat(NSLocalizedString("save.config %@", comment: "Save Config for %@"), nodeName)
			Button(buttonText) {
				var dc = Config.DisplayConfig()
				dc.gpsFormat = GpsFormats(rawValue: gpsFormat)!.protoEnumValue()
				dc.screenOnSecs = UInt32(screenOnSeconds)
				dc.autoScreenCarouselSecs = UInt32(screenCarouselInterval)
				dc.compassNorthTop = compassNorthTop
				dc.flipScreen = flipScreen
				dc.oled = OledTypes(rawValue: oledType)!.protoEnumValue()
				
				let adminMessageId =  bleManager.saveDisplayConfig(config: dc, fromUser: node!.user!, toUser: node!.user!)
				if adminMessageId > 0 {
					
					// Should show a saved successfully alert once I know that to be true
					// for now just disable the button after a successful save
					hasChanges = false
					goBack()
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
			self.hasChanges = false
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
	}
}
