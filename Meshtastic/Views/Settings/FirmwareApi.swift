//
//  FirmwareApi.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/27/23.
//

import Foundation

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

struct FirmwareReleases: Codable {
	let releases: Releases
	let pullRequests: [FirmwareRelease]
}

struct FirmwareRelease: Codable {
	let id, title: String
	let pageURL: String
	let zipURL: String

	enum CodingKeys: String, CodingKey {
		case id, title
		case pageURL = "page_url"
		case zipURL = "zip_url"
	}
}

// MARK: - Releases
struct Releases: Codable {
	let stable, alpha: [FirmwareRelease]
}

class Api : ObservableObject{

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
	
	func loadFirmwareReleaseData(completion:@escaping (FirmwareReleases) -> ()) {
		guard let url = URL(string: "https://api.meshtastic.org/github/firmware/list") else {
			print("Invalid url...")
			return
		}
		URLSession.shared.dataTask(with: url) { data, response, error in
			let firmwareReleases = try! JSONDecoder().decode(FirmwareReleases.self, from: data!)
			DispatchQueue.main.async {
				completion(firmwareReleases)
			}
		}.resume()
	}
}
