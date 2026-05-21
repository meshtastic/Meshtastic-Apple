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
	
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	let node: NodeInfoEntity?
	
	@State var hasChanges = false
	@State var screenOnSeconds = 0
	@State var screenCarouselInterval = 0
	@State var compassNorthTop = false
	@State var compassOrientation = 0
	@State var wakeOnTapOrMotion = false
	@State var flipScreen = false
	@State var oledType = 0
	@State var displayMode = 0
	@State var units = 0
	@State var use12HourClock = false
	@State var headingBold = false
	
	var body: some View {
		Form {
			ConfigHeader(title: "Display", config: \.displayConfig, node: node, onAppear: setDisplayValues)
			
			Section(header: Text("Device Screen")) {
				
				if accessoryManager.checkIsVersionSupported(forVersion: "2.3.13") {
					VStack(alignment: .leading) {
						Picker("Compass Orientation", selection: $compassOrientation) {
							ForEach(CompassOrientations.allCases) { co in
								Text(co.description)
									.tag(co.rawValue)
							}
						}
						Text("Indicates how to rotate or invert the compass output for accurate display.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				} else {
					Toggle(isOn: $compassNorthTop) {
						Label("Always point north", systemImage: "location.north.circle")
						Text("The compass heading on the screen outside of the circle will always point north.")
					}
					.tint(Color.accentColor)
				}
				
				Toggle(isOn: $use12HourClock) {
					Label("12 Hour Clock", systemImage: "clock")
					Text("Sets the screen clock format to 12-hour.")
				}
				.tint(Color.accentColor)
				
				Toggle(isOn: $headingBold) {
					Label("Bold Heading", systemImage: "bold")
					Text("Bold the heading text on the screen.")
				}
				.tint(Color.accentColor)
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
			}
			Section(header: Text("Timing and Overrides")) {
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
				
				Toggle(isOn: $wakeOnTapOrMotion) {
					Label("Wake Screen on tap or motion", systemImage: "gyroscope")
					Text("Requires that there be an accelerometer on your device.")
				}
				.tint(.accentColor)
				
				Toggle(isOn: $flipScreen) {
					Label("Flip Screen", systemImage: "pip.swap")
					Text("Flip screen vertically")
				}
				.tint(.accentColor)
				
				VStack(alignment: .leading) {
					Picker("Display Mode", selection: $displayMode ) {
						ForEach(DisplayModes.allCases) { dm in
							Text(dm.description)
						}
					}
					Text("Override default screen layout.")
						.foregroundColor(.gray)
						.font(.callout)
				}
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
			}
		}
		.disabled(!accessoryManager.isConnected || node?.displayConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					performConfigSave(
						node: node,
						context: context,
						accessoryManager: accessoryManager,
						hasChanges: $hasChanges,
						dismiss: goBack
					) { fromUser, toUser in
						var dc = Config.DisplayConfig()
						dc.screenOnSecs = UInt32(screenOnSeconds)
						dc.autoScreenCarouselSecs = UInt32(screenCarouselInterval)
						dc.compassNorthTop = compassNorthTop
						dc.compassOrientation = CompassOrientations(rawValue: compassOrientation)?.protoEnumValue() ?? .degrees0
						dc.wakeOnTapOrMotion = wakeOnTapOrMotion
						dc.flipScreen = flipScreen
						dc.oled = OledTypes(rawValue: oledType)!.protoEnumValue()
						dc.displaymode = DisplayModes(rawValue: displayMode)!.protoEnumValue()
						dc.units = Units(rawValue: units)!.protoEnumValue()
						dc.use12HClock = use12HourClock
						dc.headingBold = headingBold
						_ = try await accessoryManager.saveDisplayConfig(config: dc, fromUser: fromUser, toUser: toUser)
					}
				}
			}
		}
		.navigationTitle("Display Config")
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
				configIsNil: { $0.displayConfig == nil },
				request: accessoryManager.requestDisplayConfig
			)
		}
		.onChange(of: screenOnSeconds) { oldScreenSecs, newScreenSecs in
			if oldScreenSecs != newScreenSecs && newScreenSecs != node?.displayConfig?.screenOnSeconds ?? -1 { hasChanges = true }
		}
		.onChange(of: screenCarouselInterval) { oldCarouselSecs, newCarouselSecs in
			if oldCarouselSecs != newCarouselSecs && newCarouselSecs != node?.displayConfig?.screenCarouselInterval ?? -1 { hasChanges = true }
		}
		.onChange(of: compassNorthTop) { oldCompassNorthTop, newCompassNorthTop in
			if oldCompassNorthTop != newCompassNorthTop && newCompassNorthTop != node?.displayConfig?.compassNorthTop { hasChanges = true }
		}
		.onChange(of: compassOrientation) { oldCompassOrientation, newCompassOrientation in
			if oldCompassOrientation != newCompassOrientation && newCompassOrientation != Int(node?.displayConfig?.compassOrientation ?? 0) { hasChanges = true }
		}
		.onChange(of: wakeOnTapOrMotion) { oldWakeOnTapOrMotion, newWakeOnTapOrMotion in
			if oldWakeOnTapOrMotion != newWakeOnTapOrMotion && newWakeOnTapOrMotion != node?.displayConfig?.wakeOnTapOrMotion { hasChanges = true }
		}
		.onChange(of: flipScreen) { oldFlipScreen, newFlipScreen in
			if oldFlipScreen != newFlipScreen && newFlipScreen != node?.displayConfig?.flipScreen { hasChanges = true }
		}
		.onChange(of: oledType) { oldOledType, newOledType in
			if oldOledType != newOledType && newOledType != node?.displayConfig?.oledType ?? -1 { hasChanges = true }
		}
		.onChange(of: displayMode) { oldDisplayMode, newDisplayMode in
			if oldDisplayMode != newDisplayMode && newDisplayMode != node?.displayConfig?.displayMode ?? -1 { hasChanges = true }
		}
		.onChange(of: units) { oldUnits, newUnits in
			if oldUnits != newUnits && newUnits != node?.displayConfig?.units ?? -1 { hasChanges = true }
		}
		.onChange(of: use12HourClock) { oldUse12HourClock, newUse12HourClock in
			if oldUse12HourClock != newUse12HourClock && newUse12HourClock != node?.displayConfig?.use12HClock { hasChanges = true }
		}
		.onChange(of: headingBold) { oldHeadingBold, newHeadingBold in
			if oldHeadingBold != newHeadingBold && newHeadingBold != node?.displayConfig?.headingBold { hasChanges = true }
		}
	}
	func setDisplayValues() {
		self.screenOnSeconds = Int(node?.displayConfig?.screenOnSeconds ?? 0)
		self.screenCarouselInterval = Int(node?.displayConfig?.screenCarouselInterval ?? 0)
		self.compassNorthTop = node?.displayConfig?.compassNorthTop ?? false
		self.compassOrientation = Int(node?.displayConfig?.compassOrientation ?? 0)
		self.wakeOnTapOrMotion = node?.displayConfig?.wakeOnTapOrMotion ?? false
		self.flipScreen = node?.displayConfig?.flipScreen ?? false
		self.oledType = Int(node?.displayConfig?.oledType ?? 0)
		self.displayMode = Int(node?.displayConfig?.displayMode ?? 0)
		self.units = Int(node?.displayConfig?.units ?? 0)
		self.headingBold =  node?.displayConfig?.headingBold ?? false
		self.use12HourClock = node?.displayConfig?.use12HClock ?? false
		self.hasChanges = false
	}
}

#Preview {
	DisplayConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
