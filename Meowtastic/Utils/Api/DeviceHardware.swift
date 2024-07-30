import Foundation

struct DeviceHardware: Codable {
	let hwModel: Int
	let hwModelSlug, platformioTarget: String
	let architecture: Architecture
	let activelySupported: Bool
	let displayName: String
}
