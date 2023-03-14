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

	@State private var firmwareReleaseData: FirmwareRelease = FirmwareRelease()

	var body: some View {
		// NavigationSplitView {
		NavigationStack {

			let hwModel: HardwareModels = HardwareModels.allCases.first(where: { $0.rawValue == node?.user?.hwModel ?? "UNSET" }) ?? HardwareModels.UNSET
			Text(hwModel.firmwareStrings[0] + (node?.metadata?.firmwareVersion ?? "Unknown") )
				.font(.title3)
			VStack(alignment: .leading) {
				Text("nRF Device Firmware Update App")
					.font(.title3)
				Text("You can update your Meshtastic device over bluetooth using the Nordic DFU app.  This currently works for RAK NRF devices.")
					.font(.caption)
				Link("Get NRF DFU from the App Store", destination: URL(string: "https://apps.apple.com/us/app/nrf-device-firmware-update/id1624454660")!)
					.font(.callout)
			}
			.padding([.leading, .trailing, .bottom])
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
						let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
						if connectedNode != nil {
							if !bleManager.sendRebootOta(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
								print("Reboot Failed")
							} else {
								bleManager.disconnectPeripheral(reconnect: false)
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
			.padding([.leading, .trailing, .bottom])
			.padding(.bottom, 5)
			VStack(alignment: .leading) {
				Text("Firmware Releases")
					.font(.title3)
					.padding([.leading, .trailing])
				List {
					Section(header: Text("Stable")) {
						ForEach(firmwareReleaseData.releases?.stable ?? [], id: \.id) { fr in
							Link(destination: URL(string: fr.zipUrl ?? "")!) {
								HStack {
									Text(fr.title ?? "Unknown")
										.font(.caption)
									Spacer()
									Image(systemName: "square.and.arrow.down")
										.font(.title3)
								}
							}
						}
					}
					Section("Alpha") {
						ForEach(firmwareReleaseData.releases?.alpha ?? [], id: \.id) { fr in
							Link(destination: URL(string: fr.zipUrl ?? "")!) {
								HStack {
									Text(fr.title ?? "Unknown")
										.font(.caption)
									Spacer()
									Image(systemName: "square.and.arrow.down")
										.font(.title3)
								}
							}
						}
					}
					Section("Pull Requests") {
						ForEach(firmwareReleaseData.pullRequests ?? [], id: \.id) { fr in
							Link(destination: URL(string: fr.zipUrl ?? "")!) {
								HStack {
									Text(fr.title ?? "Unknown")
										.font(.caption)
									Spacer()
									Image(systemName: "square.and.arrow.down")
										.font(.title3)
								}
							}
						}
					}
				}
			}
			.onAppear(perform: loadData)
			.navigationTitle("Firmware Updates")
			.navigationBarTitleDisplayMode(.inline)
		}
	}

	func loadData() {

		guard let url = URL(string: "https://api.meshtastic.org/github/firmware/list") else {
			return
		}

		let request = URLRequest(url: url)
		URLSession.shared.dataTask(with: request) { data, _, _ in

			if let data = data {
				if let response_obj = try? JSONDecoder().decode(FirmwareRelease.self, from: data) {

					DispatchQueue.main.async {
						self.firmwareReleaseData = response_obj
					}
				}
			}

		}.resume()
	}
}

struct FirmwareRelease: Codable {

	var releases: Releases?       = Releases()
	var pullRequests: [PullRequests]? = []

	enum CodingKeys: String, CodingKey {

		case releases     = "releases"
		case pullRequests = "pullRequests"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)

		releases     = try values.decodeIfPresent(Releases.self, forKey: .releases     )
		pullRequests = try values.decodeIfPresent([PullRequests].self, forKey: .pullRequests )
	}

	init() {

	}
}

struct Releases: Codable {

	var stable: [Stable]? = []
	var alpha: [Alpha]?  = []

	enum CodingKeys: String, CodingKey {
		case stable = "stable"
		case alpha  = "alpha"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		stable = try values.decodeIfPresent([Stable].self, forKey: .stable )
		alpha  = try values.decodeIfPresent([Alpha].self, forKey: .alpha  )
	}

	init() {}
}

struct Alpha: Codable {

	var id: String?
	var title: String?
	var pageUrl: String?
	var zipUrl: String?

	enum CodingKeys: String, CodingKey {
		case id      = "id"
		case title   = "title"
		case pageUrl = "page_url"
		case zipUrl  = "zip_url"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id      = try values.decodeIfPresent(String.self, forKey: .id      )
		title   = try values.decodeIfPresent(String.self, forKey: .title   )
		pageUrl = try values.decodeIfPresent(String.self, forKey: .pageUrl )
		zipUrl  = try values.decodeIfPresent(String.self, forKey: .zipUrl  )
	}

	init() {}
}

struct Stable: Codable {

	var id: String?
	var title: String?
	var pageUrl: String?
	var zipUrl: String?

	enum CodingKeys: String, CodingKey {
		case id      = "id"
		case title   = "title"
		case pageUrl = "page_url"
		case zipUrl  = "zip_url"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id      = try values.decodeIfPresent(String.self, forKey: .id      )
		title   = try values.decodeIfPresent(String.self, forKey: .title   )
		pageUrl = try values.decodeIfPresent(String.self, forKey: .pageUrl )
		zipUrl  = try values.decodeIfPresent(String.self, forKey: .zipUrl  )
	}

	init() {}
}

struct PullRequests: Codable {

	var id: String?
	var title: String?
	var pageUrl: String?
	var zipUrl: String?

	enum CodingKeys: String, CodingKey {
		case id      = "id"
		case title   = "title"
		case pageUrl = "page_url"
		case zipUrl  = "zip_url"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id      = try values.decodeIfPresent(String.self, forKey: .id      )
		title   = try values.decodeIfPresent(String.self, forKey: .title   )
		pageUrl = try values.decodeIfPresent(String.self, forKey: .pageUrl )
		zipUrl  = try values.decodeIfPresent(String.self, forKey: .zipUrl  )
	}

	init() {}
}
