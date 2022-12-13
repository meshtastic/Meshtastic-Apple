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
				return NSLocalizedString("default", comment: "Default Keyboard")
			case .asciiCapable:
				return NSLocalizedString("ascii.capable", comment: "ASCII Capable Keyboard")
			case .twitter:
				return NSLocalizedString("twitter", comment: "Twitter Keyboard")
			case .emailAddress:
				return NSLocalizedString("email.address", comment: "Email Address Keyboard")
			case .numbersAndPunctuation:
				return NSLocalizedString("numbers.punctuation", comment: "Numbers and Punctuation Keyboard")
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
				return NSLocalizedString("satellite", comment: "Satellite Map Type")
			case .standard:
				return NSLocalizedString("standard", comment: "Standard Map Type")
			case .hybrid:
				return NSLocalizedString("hybrid", comment: "Hybrid Map Type")
			}
		}
	}
}

enum LocationUpdateInterval: Int, CaseIterable, Identifiable {

	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .fiveSeconds:
				return NSLocalizedString("interval.five.seconds", comment: "Five Seconds")
			case .tenSeconds:
				return NSLocalizedString("interval.ten.seconds", comment: "Ten Seconds")
			case .fifteenSeconds:
				return NSLocalizedString("interval.fifteen.seconds", comment: "Fifteen Seconds")
			case .thirtySeconds:
				return NSLocalizedString("interval.thirty.seconds", comment: "Thirty Seconds")
			case .oneMinute:
				return NSLocalizedString("interval.one.minute", comment: "One Minute")
			case .fiveMinutes:
				return NSLocalizedString("interval.five.minutes", comment: "Five Minutes")
			case .tenMinutes:
				return NSLocalizedString("interval.ten.minutes", comment: "Ten Minutes")
			case .fifteenMinutes:
				return NSLocalizedString("interval.fifteen.minutes", comment: "Fifteen Minutes")
			}
		}
	}
}

struct AppSettings: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var preferredDeviceConnected = false

	var perferredPeripheral: String {
		UserDefaults.standard.object(forKey: "preferredPeripheralName") as? String ?? ""
	}

    var body: some View {
		VStack {
			Form {
				Section(header: Text("user.details")) {

					HStack {
						Label("Name", systemImage: "person.crop.rectangle.fill")
						TextField("Username", text: $userSettings.meshtasticUsername)
							.foregroundColor(.gray)
					}
					.keyboardType(.asciiCapable)
					.disableAutocorrection(true)
					.listRowSeparator(.visible)
				}
				Section(header: Text("options")) {
					
					Picker("keyboard.type", selection: $userSettings.keyboardType) {
						ForEach(KeyboardType.allCases) { kb in
							Text(kb.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())

					 Picker("map.type", selection: $userSettings.meshMapType) {
						 ForEach(MeshMapType.allCases) { map in
							 Text(map.description)
						 }
					 }
					 .pickerStyle(DefaultPickerStyle())
					
				}
				
				Section(header: Text("phone.gps")) {
					
					Toggle(isOn: $userSettings.provideLocation) {

						Label("provide.location", systemImage: "location.circle.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if userSettings.provideLocation {
						
						Picker("update.interval", selection: $userSettings.provideLocationInterval) {
							ForEach(LocationUpdateInterval.allCases) { lu in
								Text(lu.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						
						Text("phone.gps.interval.description")
							.font(.caption)
							.listRowSeparator(.visible)
					}
				}
			}
			HStack {
				Button {
					isPresentingCoreDataResetConfirm = true
				} label: {
					Label("clear.app.data", systemImage: "trash")
						.foregroundColor(.red)
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.confirmationDialog(
					"are.you.sure",
					isPresented: $isPresentingCoreDataResetConfirm,
					titleVisibility: .visible
				) {
					Button("Erase all app data?", role: .destructive) {
						bleManager.disconnectPeripheral()
						clearCoreDataDatabase(context: context)
					}
				}
			}
		}
		.navigationTitle("app.settings")
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
		}
	}
}

struct AppSettings_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            AppSettings()
        }
    }
}
