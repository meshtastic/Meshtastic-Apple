//
//  Firmware.swift
//  Meshtastic
//
//   Copyright(c) by Garth Vander Houwen on 3/10/23.
//

import SwiftUI
import StoreKit

struct Firmware: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	var node: NodeInfoEntity?
	@State var minimumVersion = "2.2.16"
	@State var version = ""
	@State private var currentDevice: DeviceHardware?

	var body: some View {
		
		let supportedVersion = bleManager.connectedVersion == "0.0.0" ||  self.minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedSame
		VStack {
			VStack(alignment: .leading) {
				let deviceString = currentDevice?.hwModelSlug.replacingOccurrences(of: "_", with: "")

				HStack {
					VStack {
						Image(systemName: currentDevice?.activelySupported ?? false ? "checkmark.seal.fill" : "x.circle")
							.font(.largeTitle)
							.foregroundStyle(currentDevice?.activelySupported ?? false ? .green : .red)
						Text( currentDevice?.activelySupported ?? false ? "Supported" : "Unsupported")
							.foregroundStyle(.gray)
							.font(.caption2)
					}
					Text("Device Model: \(currentDevice?.displayName ?? "Unknown")")
						.font(.largeTitle)
				}
				VStack {
					Image(deviceString ?? "UNSET")
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(width: 300, height: 300)
						.cornerRadius(5)
				}
				if supportedVersion {
					Text("Your Firmware is up to date")
						.font(.title)
					Text("Current Firmware Version: \(bleManager.connectedVersion)")
						.font(.title2)
				} else {
					Text("Your Firmware is out of date")
						.font(.title)
					Text("Current Firmware Version: \(bleManager.connectedVersion), Minimium Firmware Version: \(minimumVersion)")
						.font(.title2)
				}
				if currentDevice?.architecture == Meshtastic.Architecture.nrf52840 {
					VStack(alignment: .leading) {
						/// RAK 4631
						if currentDevice?.hwModel == 9 {
							Text("nRF OTA Device Firmware Update App")
								.font(.title3)
							Text("You can update your Meshtastic device over bluetooth using the Nordic DFU app.  This currently works for RAK NRF devices.")
								.font(.caption)
							Link("Get NRF DFU from the App Store", destination: URL(string: "https://apps.apple.com/us/app/nrf-device-firmware-update/id1624454660")!)
								.font(.callout)
						} else {
							Text("OTA Updates are not supported on the this NRF Device.")
								.font(.title3)
							Link("Drag & Drop Firmware Update", destination: URL(string: "https://meshtastic.org/docs/getting-started/flashing-firmware/nrf52/drag-n-drop")!)
								.font(.callout)
						}
					}
				} else if currentDevice?.architecture == Meshtastic.Architecture.esp32 {
					VStack(alignment: .leading) {
						Text("ESP32 Device Firmware Update")
							.font(.title3)
						Text("Currently the reccomended way to update ESP32 devices is using the web flasher from a chrome based browser. It does not work on mobile devices or over BLE.")
							.font(.caption)
						Link("Web Flasher", destination: URL(string: "https://flash.meshtastic.org")!)
							.font(.callout)
							.padding(.bottom)
						Text("ESP 32 OTA update is a work in progress, click the button below to sent your device a reboot into ota admin message.")
							.font(.caption)
						HStack(alignment: .center) {
							Spacer()
							Button {
								let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? 0, context: context)
								if connectedNode != nil {
									if !bleManager.sendRebootOta(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
										print("Reboot Failed")
									}
								}
							} label: {
								Label("Send Reboot OTA", systemImage: "square.and.arrow.down")
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.regular)
							.padding(5)
							Spacer()
						}
					}
				} else {
					Text("OTA Updates are not supported on your platform.")
						.font(.title3)
					Text(node?.user?.hwModel ?? "UNSET")
						.font(.title3)
				//	Text(hwModel.platform().description)
				//		.font(.title3)
				}
			}
				.padding()
			VStack(alignment: .leading) {
				Text("Firmware Releases")
					.font(.title3)
					.padding([.leading, .trailing])
//				List {
//					Section(header: Text("Stable")) {
//						ForEach(firmwareReleaseData.releases?.stable ?? [], id: \.id) { fr in
//							Link(destination: URL(string: fr.zipUrl ?? "")!) {
//								HStack {
//									Text(fr.title ?? "Unknown")
//										.font(.caption)
//									Spacer()
//									Image(systemName: "square.and.arrow.down")
//										.font(.title3)
//								}
//							}
//						}
//					}
//					Section("Alpha") {
//						ForEach(firmwareReleaseData.releases?.alpha ?? [], id: \.id) { fr in
//							Link(destination: URL(string: fr.zipUrl ?? "")!) {
//								HStack {
//									Text(fr.title ?? "Unknown")
//										.font(.caption)
//									Spacer()
//									Image(systemName: "square.and.arrow.down")
//										.font(.title3)
//								}
//							}
//						}
//					}
//					Section("Pull Requests") {
//						ForEach(firmwareReleaseData.pullRequests ?? [], id: \.id) { fr in
//							Link(destination: URL(string: fr.zipUrl ?? "")!) {
//								HStack {
//									Text(fr.title ?? "Unknown")
//										.font(.caption)
//									Spacer()
//									Image(systemName: "square.and.arrow.down")
//										.font(.title3)
//								}
//							}
//						}
//					}
//				}
			}
			.padding(.bottom, 5)
			.onAppear() {
				Api().loadDeviceHardwareData { (hw) in
					for device in hw {
						let currentHardware = node?.user?.hwModel ?? "UNSET"
						let deviceString = device.hwModelSlug.replacingOccurrences(of: "_", with: "")
						if deviceString == currentHardware  {
							currentDevice = device
						}
					}
				}
				Api().loadFirmwareReleaseData { (bks) in
					//sel = bks
				}
			}
			.navigationTitle("Firmware Updates")
			.navigationBarTitleDisplayMode(.inline)
		}
	}
}
