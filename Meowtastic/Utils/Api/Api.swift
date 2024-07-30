import Foundation
import OSLog

final class Api: ObservableObject {
	func loadDeviceHardwareData(completion: @escaping ([DeviceHardware]) -> Void) {
		/// List from https://api.meshtastic.org/resource/deviceHardware
		guard let url = Bundle.main.url(
			forResource: "DeviceHardware.json",
			withExtension: nil
		) else {
			Logger.services.critical("Couldn't find DeviceHardware.json in main bundle.")

			return
		}

		URLSession.shared.dataTask(with: url) { data, _, _ in
			if
				let data,
				let hardware = try? JSONDecoder().decode([DeviceHardware].self, from: data)
			{
				DispatchQueue.main.async {
					completion(hardware)
				}
			}
		}
		.resume()
	}

	func loadFirmwareReleaseData(completion: @escaping (FirmwareReleases) -> Void) {
		guard let url = URL(string: "https://api.meshtastic.org/github/firmware/list") else {
			Logger.services.error("Invalid url...")

			return
		}

		URLSession.shared.dataTask(with: url) { data, _, _ in
			if
				let data,
				let firmware = try? JSONDecoder().decode(FirmwareReleases.self, from: data)
			{
				DispatchQueue.main.async {
					completion(firmware)
				}
			}
		}
		.resume()
	}
}
