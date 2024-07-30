import Foundation

struct Releases: Codable {
	let stable, alpha: [FirmwareRelease]
}

struct FirmwareReleases: Codable {
	let releases: Releases
	let pullRequests: [FirmwareRelease]
}

struct FirmwareRelease: Codable {
	enum CodingKeys: String, CodingKey {
		case id, title
		case pageURL = "page_url"
		case zipURL = "zip_url"
	}

	let id: String
	let title: String
	let pageURL: String
	let zipURL: String
}
