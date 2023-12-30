//
//  FirmwareApi.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/27/23.
//

import Foundation

struct DeviceHardware: Codable {
	var hwModel: Int
	var hwModelSlug: String
	var platformioTarget: String
	var activelySupported: Bool
	var displayName: String
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
			print(deviceHardware)
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
