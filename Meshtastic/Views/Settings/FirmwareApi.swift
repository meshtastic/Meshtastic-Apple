//
//  FirmwareApi.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/27/23.
//

import Foundation
import OSLog

/// Device Hardware API
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

/// Firmware Release Lists
struct FirmwareReleases: Codable {
	let releases: Releases
	let pullRequests: [FirmwareRelease]
}
struct Releases: Codable {
	let stable, alpha: [FirmwareRelease]
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

class Api: ObservableObject {

	func loadDeviceHardwareData(completion: @escaping ([DeviceHardware]) -> Void) {

		/// List from https://api.meshtastic.org/resource/deviceHardware
		guard let url = Bundle.main.url(forResource: "DeviceHardware.json", withExtension: nil) else {
			Logger.services.critical("Couldn't find DeviceHardware.json in main bundle.")
			return
		}

		URLSession.shared.dataTask(with: url) { data, _, _ in
			if let data = data {
				do {
					let deviceHardware = try JSONDecoder().decode([DeviceHardware].self, from: data)
					DispatchQueue.main.async {
						completion(deviceHardware)
					}
				} catch {
					Logger.services.error("JSON decode failure: \(error.localizedDescription, privacy: .public)")
				}
				return
			}
		}.resume()
	}

	func loadFirmwareReleaseData(completion: @escaping (FirmwareReleases) -> Void) {
		guard let url = URL(string: "https://api.meshtastic.org/github/firmware/list") else {
			Logger.services.error("Invalid url...")
			return
		}
		URLSession.shared.dataTask(with: url) { data, _, _ in
			if let data = data {
				do {
					let firmwareReleases = try JSONDecoder().decode(FirmwareReleases.self, from: data)
					DispatchQueue.main.async {
						completion(firmwareReleases)
					}
				} catch {
					Logger.services.error("JSON decode failure: \(error.localizedDescription, privacy: .public)")
				}
				return
			}
		}.resume()
	}
}
