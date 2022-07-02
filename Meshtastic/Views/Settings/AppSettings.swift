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

enum LocationUpdateInterval: Int, CaseIterable, Identifiable {

	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .oneMinute:
				return "One Minute"
			case .fiveMinutes:
				return "Five Minutes"
			case .tenMinutes:
				return "Ten Minutes"
			case .fifteenMinutes:
				return "Fifteen Minutes"
			}
		}
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

		VStack {

			Form {
				Section(header: Text("USER DETAILS")) {

					HStack {
						Label("Name", systemImage: "person.crop.rectangle.fill")
						TextField("Username", text: $userSettings.meshtasticUsername)
							.foregroundColor(.gray)
					}
					.keyboardType(.asciiCapable)
					.disableAutocorrection(true)
					.listRowSeparator(.visible)
					
					HStack {
						Label("Radio", systemImage: "flipphone")
						Text(userSettings.preferredPeripheralName)
							.foregroundColor(.gray)
						
					}
					Text("This option is set via the preferred radio toggle for the connected device on the bluetooth tab.")
						.font(.caption)
						.listRowSeparator(.hidden)
					Text("The preferred radio will automatically reconnect if it becomes disconnected and is still within range.")
						.font(.caption2)
						.foregroundColor(.gray)

				}
				Section(header: Text("OPTIONS")) {
					
					Toggle(isOn: $userSettings.provideLocation) {

						Label("Provide location to mesh", systemImage: "location.circle.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
					if userSettings.provideLocation {
						
						Picker(" Update Interval", selection: $userSettings.provideLocationInterval) {
							ForEach(LocationUpdateInterval.allCases) { lu in
								Text(lu.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						
						Text("How frequently your phone will send your location to the device, location updates to the mesh are managed by the device.")
							.font(.caption)
							.listRowSeparator(.visible)
					}

					Picker("Keyboard Type", selection: $userSettings.keyboardType) {
						ForEach(KeyboardType.allCases) { kb in
							Text(kb.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())

					 Picker("Map Type", selection: $userSettings.meshMapType) {
						 ForEach(MeshMapType.allCases) { map in
							 Text(map.description)
						 }
					 }
					 .pickerStyle(DefaultPickerStyle())
					
				}
				Section(header: Text("DEBUG")) {

					NavigationLink(destination: MeshLog()) {
						Text("View Mesh Log")
					}
				}
			}
		}
		.navigationTitle("App Settings")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			self.bleManager.context = context
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
