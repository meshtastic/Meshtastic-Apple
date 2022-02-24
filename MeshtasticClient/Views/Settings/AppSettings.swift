import Foundation
import Combine
import SwiftUI
import SwiftProtobuf
import MapKit

enum KeyboardType: Int, CaseIterable, Identifiable {

	case defaultKeyboard = 0
	case asciiCapable = 1
	case twitter = 9
	case emailAddress = 7
	case numbersAndPunctuation = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .defaultKeyboard:
				return "Default"
			case .asciiCapable:
				return "ASCII Capable"
			case .twitter:
				return "Twitter"
			case .emailAddress:
				return "Email Address"
			case .numbersAndPunctuation:
				return "Numbers and Punctuation"
			}
		}
	}
}

enum MeshMapType: String, CaseIterable, Identifiable {

	case satellite = "satellite"
	case hybrid = "hybrid"
	case standard = "standard"

	var id: String { self.rawValue }

	var description: String {
		get {
			switch self {
			case .satellite:
				return "Satellite"
			case .standard:
				return "Standard"
			case .hybrid:
				return "Hybrid"
			}
		}
	}
}

class UserSettings: ObservableObject {
//	@Published var meshtasticUsername: String {
//		didSet {
//			UserDefaults.standard.set(meshtasticUsername, forKey: "meshtasticusername")
//		}
//	}
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

		// self.meshtasticUsername = UserDefaults.standard.object(forKey: "meshtasticusername") as? String ?? ""
		self.preferredPeripheralName = UserDefaults.standard.object(forKey: "preferredPeripheralName") as? String ?? ""
		self.preferredPeripheralId = UserDefaults.standard.object(forKey: "preferredPeripheralId") as? String ?? ""
		self.provideLocation = UserDefaults.standard.object(forKey: "provideLocation") as? Bool ?? false
		self.keyboardType = UserDefaults.standard.object(forKey: "keyboardType") as? Int ?? 0
		self.meshActivityLog = UserDefaults.standard.object(forKey: "meshActivityLog") as? Bool ?? false
		self.meshMapType = UserDefaults.standard.string(forKey: "meshMapType") ?? "hybrid"
		self.meshMapCustomTileServer = UserDefaults.standard.string(forKey: "meshMapCustomTileServer") ?? ""
	}
}

struct AppSettings: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings

	@State private var preferredDeviceConnected = false

	var perferredPeripheral: String {
		UserDefaults.standard.object(forKey: "preferredPeripheralName") as? String ?? ""
	}

    var body: some View {

        NavigationView {

            GeometryReader { _ in

				List {
					Section(header: Text("USER DETAILS")) {

//						HStack {
//							Label("Name", systemImage: "person.crop.rectangle.fill")
//							TextField("Username", text: $userSettings.meshtasticUsername)
//								.foregroundColor(.gray)
//						}
//						.listRowSeparator(.visible)
						Toggle(isOn: $userSettings.provideLocation) {

							Label("Provide location to mesh", systemImage: "location.circle.fill")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)
						Label("Preferred Radio", systemImage: "flipphone")
							.listRowSeparator(.hidden)
						Text(userSettings.preferredPeripheralName)
								.foregroundColor(.gray)
						Text("This option is set via the preferred radio toggle for the connected device on the bluetooth tab.")
							.font(.caption)
							.listRowSeparator(.hidden)
						Text("The preferred radio will automatically reconnect if it becomes disconnected and is still within range.  This device is assumed to be the primary radio used for messaging.")
							.font(.caption2)
							.foregroundColor(.gray)

					}
					Section(header: Text("MESSAGING OPTIONS")) {

						Picker("Keyboard Type", selection: $userSettings.keyboardType) {
							ForEach(KeyboardType.allCases) { kb in
								Text(kb.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
					}
					Section(header: Text("MAP OPTIONS")) {
						 Picker("Map Type", selection: $userSettings.meshMapType) {
							 ForEach(MeshMapType.allCases) { map in
								 Text(map.description)
							 }
						 }
						 .pickerStyle(DefaultPickerStyle())
					//	TextField("Custom Tile Server", text: $userSettings.meshMapCustomTileServer)
					}
					Section(header: Text("DEBUG")) {
						 Toggle(isOn: $userSettings.meshActivityLog) {

							Label("Log all Mesh activity", systemImage: "network")
						 }
						 .toggleStyle(SwitchToggleStyle(tint: .accentColor))
						if userSettings.meshActivityLog {
							NavigationLink(destination: MeshLog()) {
							Text("View Mesh Log")
						}
							.listRowSeparator(.visible)
						}
					}
				}
			}
            .navigationTitle("App Settings")
			.navigationBarItems(trailing:

				ZStack {

					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "???")
			})
			.onAppear {

				self.bleManager.context = context
			}
        }
		.navigationViewStyle(StackNavigationViewStyle())
	}
}

struct AppSettings_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            AppSettings()
        }
    }
}
