//
//  APIStructs.swift
//  Meshtastic
//
//  Created by jake on 12/12/25.
//

/// Device Hardware API
struct DeviceHardware: Codable {
	let hwModel: Int
	let hwModelSlug: String
	let platformioTarget: String
	let architecture: Architecture
	let activelySupported: Bool
	let displayName: String
	let supportLevel: Int?
	let tags: [String]?
	let images: [String]?
	let requiresDfu: Bool?
	let hasInkHud: Bool?
	let partitionScheme: String?
	let hasMui: Bool?
}
enum Architecture: String, Codable, Identifiable {
	case esp32 = "esp32"
	case esp32C3 = "esp32-c3"
	case esp32S3 = "esp32-s3"
	case nrf52840 = "nrf52840"
	case rp2040 = "rp2040"
	case esp32C6 = "esp32-c6"

	var id: String { rawValue }
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
	let releaseNotes: String

	enum CodingKeys: String, CodingKey {
		case id, title
		case pageURL = "page_url"
		case zipURL = "zip_url"
		case releaseNotes = "release_notes"
	}
	
	enum ReleaseType: String {
		case stable = "Stable"
		case alpha = "Alpha"
		case unlisted = "Unlisted"
	}
}
