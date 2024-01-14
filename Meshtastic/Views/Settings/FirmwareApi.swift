//
//  FirmwareApi.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/27/23.
//

import Foundation

//struct DeviceHardware: Codable {
//	var hwModel: Int
//	var hwModelSlug: String
//	var platformioTarget: String
//	var activelySupported: Bool
//	var displayName: String
//}

struct DeviceHardware: Codable {
	let hwModel: Int
	let hwModelSlug, platformioTarget: String
	let architecture: Architecture
	let activelySupported: Bool
	let displayName: String
}

enum Architecture: String, Codable {
	case esp32 = "esp32"
	case esp32C3 = "esp32-c3"
	case esp32S3 = "esp32-s3"
	case nrf52840 = "nrf52840"
	case rp2040 = "rp2040"
}

class Api : ObservableObject{
//	@Published var devices = [DeviceHardware]()
	
	func loadDeviceHardwareData(completion:@escaping ([DeviceHardware]) -> ()) {
		guard let url = URL(string: "https://api.meshtastic.org/resource/deviceHardware") else {
			print("Invalid url...")
			return
		}
		URLSession.shared.dataTask(with: url) { data, response, error in
			let deviceHardware = try! JSONDecoder().decode([DeviceHardware].self, from: data!)
			//print(deviceHardware)
			DispatchQueue.main.async {
				completion(deviceHardware)
			}
		}.resume()
	}
//	func loadFirmwareReleaseData(completion:@escaping ([FirmwareRelease]) -> ()) {
//		guard let url = URL(string: "https://api.meshtastic.org/github/firmware/list") else {
//			print("Invalid url...")
//			return
//		}
//		URLSession.shared.dataTask(with: url) { data, response, error in
//			let deviceHardware = try! JSONDecoder().decode([FirmwareRelease].self, from: data!)
//			print(deviceHardware)
//			DispatchQueue.main.async {
//				completion(deviceHardware)
//			}
//		}.resume()
//	}
}
