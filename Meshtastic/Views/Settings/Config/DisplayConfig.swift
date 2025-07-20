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
	@EnvironmentObject var accessoryManager: AccessoryManager
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
	@State var use12HourClock = false

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
				Toggle(isOn: $use12HourClock) {
					Label("12 Hour Clock", systemImage: "clock")
					Text("Sets the screen clock format to 12-hour.")
				}
				.tint(Color.accentColor)
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
		.disabled(!accessoryManager.isConnected || node?.displayConfig == nil)

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			if let deviceNum = accessoryManager.activeDeviceNum, let connectedNode = getNodeInfo(id: deviceNum, context: context) {
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
				dc.use12HClock = use12HourClock

				Task {
					_ = try await accessoryManager.saveDisplayConfig(config: dc, fromUser: connectedNode.user!, toUser: node!.user!)
					Task { @MainActor in
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
		}

		.navigationTitle("Display Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")

			}
		)
		.onFirstAppear {
			// Need to request a DisplayConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				if let connectedNode = getNodeInfo(id: deviceNum, context: context) {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.displayConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired display config requesting via PKI admin")
										try await accessoryManager.requestDisplayConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.error("🚨 Display config request failed")
									}
								}
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
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
		.onChange(of: wakeOnTapOrMotion) { oldWakeOnTapOrMotion, newWakeOnTapOrMotion in
			if oldWakeOnTapOrMotion != newWakeOnTapOrMotion && newWakeOnTapOrMotion != node?.displayConfig?.wakeOnTapOrMotion { hasChanges = true }
		}
		.onChange(of: gpsFormat) { oldGpsFormat, newGpsFormat in
			if oldGpsFormat != newGpsFormat && newGpsFormat != node?.displayConfig?.gpsFormat ?? -1 { hasChanges = true }
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
			self.use12HourClock =  node?.displayConfig?.use12HClock ?? false
			self.hasChanges = node?.displayConfig?.use12HClock ?? false
	}
}
