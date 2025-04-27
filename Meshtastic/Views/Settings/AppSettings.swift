import Foundation
import Combine
import SwiftUI
import SwiftProtobuf
import MapKit
import OSLog

struct AppSettings: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State var totalDownloadedTileSize = ""
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var isPresentingDeleteMapTilesConfirm = false
	@AppStorage("environmentEnableWeatherKit") private var  environmentEnableWeatherKit: Bool = true
	@AppStorage("enableAdministration") private var  enableAdministration: Bool = false
	var body: some View {
		VStack {
			Form {
				Section(header: Text("App Settings")) {
					Button("Open Settings", systemImage: "gear") {
						// Get the settings URL and open it
						if let url = URL(string: UIApplication.openSettingsURLString) {
							UIApplication.shared.open(url)
						}
					}
					Toggle(isOn: $enableAdministration) {
						Label("Administration", systemImage: "gearshape.2")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("PKI based node administration, requires firmware version 2.5+")
						.foregroundStyle(.secondary)
						.font(.caption)
				}
				Section(header: Text("environment")) {
					VStack(alignment: .leading) {
						Toggle(isOn: $environmentEnableWeatherKit) {
							Label("Weather Conditions", systemImage: "cloud.sun")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
				}
				Section(header: Text("App Data")) {
					Button {
						isPresentingCoreDataResetConfirm = true
					} label: {
						Label("Clear App Data", systemImage: "trash")
							.foregroundColor(.red)
					}
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingCoreDataResetConfirm,
						titleVisibility: .visible
					) {
						Button("Erase all app data?", role: .destructive) {
							bleManager.disconnectPeripheral()
							/// Delete any database backups too
							if var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
								url = url.appendingPathComponent("backup").appendingPathComponent(String(UserDefaults.preferredPeripheralNum))
								do {
									try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite"))
									/// Delete -shm file
									do {
										try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite-wal"))
										do {
											try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite-shm"))
										} catch {
											Logger.services.error("🗄 Error Deleting Meshtastic.sqlite-shm file \(error, privacy: .public)")
										}
									} catch {
										Logger.services.error("🗄 Error Deleting Meshtastic.sqlite-wal file \(error, privacy: .public)")
									}
								} catch {
									Logger.services.error("🗄 Error Deleting Meshtastic.sqlite file \(error, privacy: .public)")
								}
							}
							clearCoreDataDatabase(context: context, includeRoutes: true)
							context.refreshAllObjects()
						}
					}
					Button {
						UserDefaults.standard.reset()
					} label: {
						Label("Reset App Settings", systemImage: "arrow.counterclockwise.circle")
							.foregroundColor(.red)
					}
				}
			}
		}
		.navigationTitle("App Settings")
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
	}
}
