import Foundation
import Combine
import SwiftUI
import SwiftProtobuf
import MapKit

struct AppSettings: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	@StateObject var locationHelper = LocationHelper()
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var preferredDeviceConnected = false
	
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
							.foregroundColor(.gray)
					}
					Picker("map.usertrackingmode", selection: $userSettings.meshMapUserTrackingMode) {
						ForEach(UserTrackingModes.allCases) { utm in
							Text(utm.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("When follow or follow with heading are selected maps will automatically center on the location of the GPS on the connected phone.")
						.font(.caption)
						.foregroundColor(.gray)
				}
				
				Section(header: Text("map options")) {
					
					Picker("map.type", selection: $userSettings.meshMapType) {
						ForEach(MeshMapType.allCases) { map in
							Text(map.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					if userSettings.meshMapUserTrackingMode == 0 {
						
						Toggle(isOn: $userSettings.meshMapRecentering) {
							
							Label("map.recentering", systemImage: "camera.metering.center.weighted")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
					Toggle(isOn: $userSettings.meshMapShowNodeHistory) {
						
						Label("Show Node History", systemImage: "building.columns.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $userSettings.meshMapShowRouteLines) {
						
						Label("Show Route Lines", systemImage: "road.lanes")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
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
						UserDefaults.standard.reset()
						UserDefaults.standard.synchronize()
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
		.onChange(of: userSettings.provideLocation) { _ in
			
			if bleManager.connectedPeripheral != nil {
				self.bleManager.sendWantConfig()
			}
		}
	}
}
