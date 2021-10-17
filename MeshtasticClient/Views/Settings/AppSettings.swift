import Foundation
import Combine
import SwiftUI
import SwiftProtobuf

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
					return "ascii Capable"
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

class UserSettings: ObservableObject {
	@Published var username: String {
		didSet {
			UserDefaults.standard.set(username, forKey: "username")
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
	
	init() {
		self.username = UserDefaults.standard.object(forKey: "username") as? String ?? ""
		self.provideLocation = UserDefaults.standard.object(forKey: "provideLocation") as? Bool ?? false
		self.keyboardType = UserDefaults.standard.object(forKey: "keyboardType") as? Int ?? 0
	}
}

struct AppSettings: View {
	
	@ObservedObject var userSettings = UserSettings()
	
    var body: some View {
        NavigationView {
            
            GeometryReader { bounds in
                
				Form {
					Section(header: Text("USER DETAILS")) {
						HStack{
							
							Text("User Name")
							TextField("Username", text: $userSettings.username)
								.foregroundColor(.gray)
						}
						Toggle(isOn: $userSettings.provideLocation) {
							
							Text("Provide location to mesh")
						}
					}
					Section(header: Text("MESSAGING OPTIONS")) {
					
						Picker("Keyboard Type", selection: $userSettings.keyboardType) {
							ForEach(KeyboardType.allCases) { kb in
								Text(kb.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
					}
				}
			}
            .navigationTitle("App Settings")
        }
		.navigationViewStyle(StackNavigationViewStyle())    }
}

struct AppSettings_Previews: PreviewProvider {
    static let meshData = MeshData()

    static var previews: some View {
        Group {
            AppSettings()
        }
    }
}
