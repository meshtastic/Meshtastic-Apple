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
	@State var minimumVersion = "2.3.7"
	@State var version = ""
	@State private var currentDevice: DeviceHardware?
	@State private var latestStable: FirmwareRelease?
	@State private var latestAlpha: FirmwareRelease?
	
	var body: some View {
		
		let supportedVersion = bleManager.connectedVersion == "0.0.0" ||  self.minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(bleManager.connectedVersion, options: .numeric) == .orderedSame
		ScrollView {
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
						.fixedSize(horizontal: false, vertical: true)
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
						.fixedSize(horizontal: false, vertical: true)
						.foregroundStyle(.green)
						.font(.title2)
						.padding(.bottom)
					Text("Current Firmware Version: \(bleManager.connectedVersion)")
						.fixedSize(horizontal: false, vertical: true)
						.font(.title3)
						.padding(.bottom)
				} else {
					Text("Your Firmware is out of date")
						.fixedSize(horizontal: false, vertical: true)
						.foregroundStyle(.red)
						.font(.title2)
						.padding(.bottom)
					Text("Current Firmware Version: \(bleManager.connectedVersion), Minimium Firmware Version: \(minimumVersion)")
						.fixedSize(horizontal: false, vertical: true)
						.font(.title3)
						.padding(.bottom)
				}
				Divider()
				Text("How to update Firmware")
					.fixedSize(horizontal: false, vertical: true)
					.font(.title2)
					.padding(.bottom)
				
				Text("Get the latest stable firmware")
					.fixedSize(horizontal: false, vertical: true)
					.font(.callout)
				Link("\(latestStable?.title ?? "unknown".localized)", destination: URL(string: "\(latestStable?.zipURL ?? "https://meshtastic.org")")!)
					.font(.caption)
				Link("Release Notes", destination: URL(string: "\(latestStable?.pageURL ?? "https://meshtastic.org")")!)
					.font(.caption)
					.padding(.bottom)
				
				Text("Get the latest alpha firmware")
					.fixedSize(horizontal: false, vertical: true)
					.font(.callout)
				Link("\(latestAlpha?.title ?? "unknown".localized)", destination: URL(string: "\(latestAlpha?.zipURL ?? "https://meshtastic.org")")!)
					.font(.caption)
				Link("Release Notes", destination: URL(string: "\(latestAlpha?.pageURL ?? "https://meshtastic.org")")!)
					.font(.caption)
					.padding(.bottom)
				
				if currentDevice?.architecture == Meshtastic.Architecture.nrf52840 {
					VStack(alignment: .leading) {
						
						Text("Drag & Drop is the reccomended way to update firmware for NRF devices. If your iPhone or iPad is USB-C it will work with your regular USB-C charging cable, for lightning devices you need the Apple Lightning to USB camera adaptor.")
							.fixedSize(horizontal: false, vertical: true)
							.foregroundStyle(.gray)
							.font(.caption)
						Link("Drag & Drop Firmware Update Documentation", destination: URL(string: "https://meshtastic.org/docs/getting-started/flashing-firmware/nrf52/drag-n-drop")!)
							.font(.caption)
							.padding(.bottom)
						VStack {
							Text("If it is hard to access your device's reset button enter DFU mode here.")
								.fixedSize(horizontal: false, vertical: true)
								.foregroundStyle(.gray)
								.font(.caption)
							Button {
								let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? 0, context: context)
								if connectedNode != nil {
									
									if bleManager.sendEnterDfuMode(fromUser: connectedNode!.user!, toUser: node!.user!) {
										DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
											bleManager.disconnectPeripheral(reconnect: false)
										}
									} else {
										print("Enter DFU Failed")
									}
								}
							} label: {
								Label("Enter DFU Mode", systemImage: "square.and.arrow.down")
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.regular)
							.padding(5)
						}
						Spacer()
						/// RAK 4631
						if currentDevice?.hwModel == 9 {
							Text("You can also update your Meshtastic device over bluetooth using the Nordic DFU app.")
								.fixedSize(horizontal: false, vertical: true)
								.foregroundStyle(.gray)
								.font(.caption)
							Link("Get NRF DFU from the App Store", destination: URL(string: "https://apps.apple.com/us/app/nrf-device-firmware-update/id1624454660")!)
								.font(.callout)
								.padding(.bottom)
						} else {
							Text("OTA Updates are not supported on the this NRF Device.")
								.font(.title3)
							Link("Drag & Drop Firmware Update", destination: URL(string: "https://meshtastic.org/docs/getting-started/flashing-firmware/nrf52/drag-n-drop")!)
								.font(.callout)
						}
					}
				} else if currentDevice?.architecture == Meshtastic.Architecture.esp32 || currentDevice?.architecture == Meshtastic.Architecture.esp32S3 || currentDevice?.architecture == Meshtastic.Architecture.esp32C3 {
					VStack(alignment: .leading) {
						Text("ESP32 Device Firmware Update")
							.font(.title3)
						Text("Currently the reccomended way to update ESP32 devices is using the web flasher on a desktop computer from a chrome based browser. It does not work on mobile devices or over BLE.")
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
					Text ( currentDevice?.architecture.rawValue ?? "UNKNOWN")
						.font(.title3)
				}
			}
			.padding()
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
				Api().loadFirmwareReleaseData { (fw) in
					latestStable = fw.releases.stable.first
					latestAlpha = fw.releases.alpha.first
				}
			}
			.navigationTitle("Firmware Updates")
			.navigationBarTitleDisplayMode(.inline)
		}
	}
}
