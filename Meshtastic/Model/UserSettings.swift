//
//  UserSettings.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 6/9/22.
//

import Foundation

class UserSettings: ObservableObject {
	@Published var meshtasticUsername: String {
		didSet {
			UserDefaults.standard.set(meshtasticUsername, forKey: "meshtasticusername")
		}
	}
	@Published var preferredPeripheralId: String {
		didSet {
			UserDefaults.standard.set(preferredPeripheralId, forKey: "preferredPeripheralId")
			UserDefaults.standard.synchronize()
		}
	}
	@Published var preferredNodeNum: Int64 {
		didSet {
			UserDefaults.standard.set(preferredNodeNum, forKey: "preferredNodeNum")
			UserDefaults.standard.synchronize()
		}
	}
	@Published var provideLocation: Bool {
		didSet {
			UserDefaults.standard.set(provideLocation, forKey: "provideLocation")
		}
	}
	@Published var provideLocationInterval: Int {
		didSet {
			UserDefaults.standard.set(provideLocationInterval, forKey: "provideLocationInterval")
		}
	}
	@Published var keyboardType: Int {
		didSet {
			UserDefaults.standard.set(keyboardType, forKey: "keyboardType")
		}
	}
	@Published var meshMapType: String {
		didSet {
			UserDefaults.standard.set(meshMapType, forKey: "meshMapType")
		}
	}
	@Published var meshMapCenteringMode: Int {
		didSet {
			UserDefaults.standard.set(meshMapCenteringMode, forKey: "meshMapCenteringMode")
			UserDefaults.standard.synchronize()
		}
	}
	@Published var meshMapRecentering: Bool {
		didSet {
			UserDefaults.standard.set(meshMapCenteringMode, forKey: "meshMapRecentering")
			UserDefaults.standard.synchronize()
		}
	}
	@Published var meshMapCustomTileServer: String {
		didSet {
			UserDefaults.standard.set(meshMapCustomTileServer, forKey: "meshMapCustomTileServer")
		}
	}

	init() {

		self.meshtasticUsername = UserDefaults.standard.object(forKey: "meshtasticusername") as? String ?? ""
		self.preferredPeripheralId = UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? ""
		self.preferredNodeNum = UserDefaults.standard.object(forKey: "preferredNodeNum") as? Int64 ?? 0
		self.provideLocation = UserDefaults.standard.object(forKey: "provideLocation") as? Bool ?? false
		self.provideLocationInterval = UserDefaults.standard.object(forKey: "provideLocationInterval") as? Int ?? 900
		self.keyboardType = UserDefaults.standard.object(forKey: "keyboardType") as? Int ?? 0
		self.meshMapType = UserDefaults.standard.string(forKey: "meshMapType") ?? "standard"
		self.meshMapCenteringMode = UserDefaults.standard.object(forKey: "meshMapCenteringMode") as? Int ?? 0
		self.meshMapRecentering = UserDefaults.standard.object(forKey: "meshMapRecentering") as? Bool ?? true
		self.meshMapCustomTileServer = UserDefaults.standard.string(forKey: "meshMapCustomTileServer") ?? ""
	}
}
