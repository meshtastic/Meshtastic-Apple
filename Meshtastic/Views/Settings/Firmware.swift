//
//  Firmware.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/10/23.
//

//
//  About.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/6/22.
//
import SwiftUI
import StoreKit

struct Firmware: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	var node: NodeInfoEntity?
	@State var minimumVersion = "2.2.16"
	@State var version = ""
	//var currentDevice: DeviceHardware

	var body: some View {
		// NavigationSplitView {
		VStack {
			let hwModel: HardwareModels = HardwareModels.allCases.first(where: { $0.rawValue == node?.user?.hwModel ?? "UNSET" }) ?? HardwareModels.UNSET
			VStack(alignment: .leading) {
				Text("Current Version: \(bleManager.connectedVersion)")
					.font(.largeTitle)
				Text("Your device supports the following firmware: ")
					.font(.callout)
				HStack {
					ForEach(hwModel.firmwareStrings, id: \.self) { fs in
						Text(fs).font(.callout)
					}
				}
				.padding(.bottom)

				if hwModel.platform() == HardwarePlatforms.nrf52 {
					VStack(alignment: .leading) {
						if hwModel == HardwareModels.RAK4631 {
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
				} else if hwModel.platform() == HardwarePlatforms.esp32 {
					VStack(alignment: .leading) {
						Text("ESP32 Device Firmware Update")
							.font(.title3)
						Text("Currently the reccomended way to update ESP32 devices is using the web flasher from a chrome based browser. It does not work on mobile devices or over BLE.")
							.font(.caption)
						Link("Web Flasher", destination: URL(string: "https://flasher.meshtastic.org")!)
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
					Text(hwModel.platform().description)
						.font(.title3)
				}
			}
			Spacer()
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
						if device.hwModelSlug == node?.user?.hwModel ?? "UNSET" {
							print("Selected: \(device)")
						}
					}
				}
//				Api().loadFirmwareReleaseData { (bks) in
//					//sel = bks
//				}
			}
			.navigationTitle("Firmware Updates")
			.navigationBarTitleDisplayMode(.inline)
		}
	}
}

//struct FirmwareRelease: Codable {
//	var releases: Releases?       = Releases()
//	var pullRequests: [PullRequests]? = []
//	enum CodingKeys: String, CodingKey {
//		case releases     = "Releases"
//		case pullRequests = "Pull Requests"
//	}
//	init(from decoder: Decoder) throws {
//		let values = try decoder.container(keyedBy: CodingKeys.self)
//		releases     = try values.decodeIfPresent(Releases.self, forKey: .releases     )
//		pullRequests = try values.decodeIfPresent([PullRequests].self, forKey: .pullRequests )
//	}
//	init() {
//	}
//}
//
//struct Releases: Codable {
//	var stable: [Stable]? = []
//	var alpha: [Alpha]?  = []
//	enum CodingKeys: String, CodingKey {
//		case stable = "Stable"
//		case alpha  = "Alpha"
//	}
//	init(from decoder: Decoder) throws {
//		let values = try decoder.container(keyedBy: CodingKeys.self)
//		stable = try values.decodeIfPresent([Stable].self, forKey: .stable )
//		alpha  = try values.decodeIfPresent([Alpha].self, forKey: .alpha  )
//	}
//	init() {}
//}
//
//struct Alpha: Codable {
//	var id: String?
//	var title: String?
//	var pageUrl: String?
//	var zipUrl: String?
//	enum CodingKeys: String, CodingKey {
//		case id      = "id"
//		case title   = "title"
//		case pageUrl = "page_url"
//		case zipUrl  = "zip_url"
//	}
//	init(from decoder: Decoder) throws {
//		let values = try decoder.container(keyedBy: CodingKeys.self)
//		id      = try values.decodeIfPresent(String.self, forKey: .id      )
//		title   = try values.decodeIfPresent(String.self, forKey: .title   )
//		pageUrl = try values.decodeIfPresent(String.self, forKey: .pageUrl )
//		zipUrl  = try values.decodeIfPresent(String.self, forKey: .zipUrl  )
//	}
//	init() {}
//}
//
//struct Stable: Codable {
//	var id: String?
//	var title: String?
//	var pageUrl: String?
//	var zipUrl: String?
//	enum CodingKeys: String, CodingKey {
//		case id      = "id"
//		case title   = "title"
//		case pageUrl = "page_url"
//		case zipUrl  = "zip_url"
//	}
//	init(from decoder: Decoder) throws {
//		let values = try decoder.container(keyedBy: CodingKeys.self)
//		id      = try values.decodeIfPresent(String.self, forKey: .id      )
//		title   = try values.decodeIfPresent(String.self, forKey: .title   )
//		pageUrl = try values.decodeIfPresent(String.self, forKey: .pageUrl )
//		zipUrl  = try values.decodeIfPresent(String.self, forKey: .zipUrl  )
//	}
//	init() {}
//}
//
//struct PullRequests: Codable {
//	var id: String?
//	var title: String?
//	var pageUrl: String?
//	var zipUrl: String?
//	enum CodingKeys: String, CodingKey {
//		case id      = "id"
//		case title   = "title"
//		case pageUrl = "page_url"
//		case zipUrl  = "zip_url"
//	}
//	init(from decoder: Decoder) throws {
//		let values = try decoder.container(keyedBy: CodingKeys.self)
//		id      = try values.decodeIfPresent(String.self, forKey: .id      )
//		title   = try values.decodeIfPresent(String.self, forKey: .title   )
//		pageUrl = try values.decodeIfPresent(String.self, forKey: .pageUrl )
//		zipUrl  = try values.decodeIfPresent(String.self, forKey: .zipUrl  )
//	}
//	init() {}
//}
