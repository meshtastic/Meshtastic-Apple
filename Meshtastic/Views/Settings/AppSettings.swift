import Foundation
import Combine
import SwiftUI
import SwiftProtobuf
import MapKit
import OSLog

struct AppSettings: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State var totalDownloadedTileSize = ""
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var isPresentingDeleteMapTilesConfirm = false
	@State private var isPresentingAppIconSheet = false
	@State private var purgeStaleNodes: Bool = false
	@AppStorage("purgeStaleNodeDays") private var  purgeStaleNodeDays: Double = 0
	@AppStorage("environmentEnableWeatherKit") private var  environmentEnableWeatherKit: Bool = true
	@AppStorage("enableAdministration") private var  enableAdministration: Bool = false
	@AppStorage("usageDataAndCrashReporting") private var usageDataAndCrashReporting: Bool = true
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
					Toggle(isOn: $usageDataAndCrashReporting) {
						Label("Usage and Crash Data", systemImage: "pencil.and.list.clipboard")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("Provide anonymous usage statistics and crash reports.")
						.foregroundStyle(.secondary)
						.font(.caption)
					Button {
						isPresentingAppIconSheet.toggle()
					} label: {
						Label("App Icon", systemImage: "app")
					}
					.sheet(isPresented: $isPresentingAppIconSheet) {
						AppIconPicker(isPresenting: self.$isPresentingAppIconSheet)
					}
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
					Toggle(isOn: $purgeStaleNodes ) {
						Label {
							Text("Clear Stale Nodes")
						} icon: {
							Image(systemName: "list.bullet.circle")
						}
					}
					.onFirstAppear {
						purgeStaleNodes = purgeStaleNodeDays > 0
						Logger.services.info("ℹ️ Purge Stale Nodes toggle initialized to \(purgeStaleNodes)")
					}
					.onChange(of: purgeStaleNodes) { _, newValue in
						purgeStaleNodeDays = purgeStaleNodeDays > 0 ? purgeStaleNodeDays : 7
						purgeStaleNodeDays = newValue ? purgeStaleNodeDays : 0
						Logger.services.info("ℹ️ Purge Stale Nodes changed to \(purgeStaleNodeDays)")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					.listRowSeparator(purgeStaleNodes ? .hidden : .visible)
					if purgeStaleNodes {
						VStack(alignment: .leading) {
							Text(String(localized: "After \(Int(purgeStaleNodeDays)) Days"))
							Slider(value: $purgeStaleNodeDays, in: 1...180, step: 1) {
							} minimumValueLabel: {
								Text("1")
							} maximumValueLabel: {
								Text("180")
							}
						}
						Text("Favorited and ignored nodes are always retained. Nodes without PKC keys are cleared from the app database on the schedule set by the user, nodes with PKC keys are cleared only if the interval is set to 7 days or longer. This feature only purges nodes from the app that are not stored in the device node database.")
							.foregroundStyle(.secondary)
							.font(idiom == .phone ? .caption : .callout)
					}
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
