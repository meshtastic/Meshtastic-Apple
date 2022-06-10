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
	@Published var preferredPeripheralName: String {
		didSet {
			UserDefaults.standard.set(preferredPeripheralName, forKey: "preferredPeripheralName")
		}
	}
	@Published var preferredPeripheralId: String {
		didSet {
			UserDefaults.standard.set(preferredPeripheralId, forKey: "preferredPeripheralId")
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
	@Published var meshActivityLog: Bool {
		didSet {
			UserDefaults.standard.set(meshActivityLog, forKey: "meshActivityLog")
		}
	}

	@Published var meshMapType: String {
		didSet {
			UserDefaults.standard.set(meshMapType, forKey: "meshMapType")
		}
	}
	@Published var meshMapCustomTileServer: String {
		didSet {
			UserDefaults.standard.set(meshMapCustomTileServer, forKey: "meshMapCustomTileServer")
		}
	}

	init() {

		self.meshtasticUsername = UserDefaults.standard.object(forKey: "meshtasticusername") as? String ?? ""
		self.preferredPeripheralName = UserDefaults.standard.object(forKey: "preferredPeripheralName") as? String ?? ""
		self.preferredPeripheralId = UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? ""
		self.provideLocation = UserDefaults.standard.object(forKey: "provideLocation") as? Bool ?? false
		self.provideLocationInterval = UserDefaults.standard.object(forKey: "provideLocationInterval") as? Int ?? 900
		self.keyboardType = UserDefaults.standard.object(forKey: "keyboardType") as? Int ?? 0
		self.meshActivityLog = UserDefaults.standard.object(forKey: "meshActivityLog") as? Bool ?? false
		self.meshMapType = UserDefaults.standard.string(forKey: "meshMapType") ?? "hybrid"
		self.meshMapCustomTileServer = UserDefaults.standard.string(forKey: "meshMapCustomTileServer") ?? ""
	}
}
