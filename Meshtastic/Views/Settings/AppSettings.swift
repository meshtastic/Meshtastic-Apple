import Foundation
import Combine
import SwiftUI
import SwiftProtobuf
import MapKit
import DatadogCore
import OSLog

struct AppSettings: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var totalDownloadedTileSize = ""
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var isPresentingDeleteMapTilesConfirm = false
	@State private var isPresentingAppIconSheet = false
	@State private var purgeStaleNodes: Bool = false
	@State private var showAutoConnect: Bool = false
	@AppStorage("purgeStaleNodeDays") private var  purgeStaleNodeDays: Double = 0
	@AppStorage("environmentEnableWeatherKit") private var  environmentEnableWeatherKit: Bool = true
	@AppStorage("enableAdministration") private var  enableAdministration: Bool = false
	@AppStorage("usageDataAndCrashReporting") private var usageDataAndCrashReporting: Bool = true
	
	let autoconnectBinding = Binding<Bool>(get: {
		return UserDefaults.autoconnectOnDiscovery
	}, set: { newValue in
		UserDefaults.autoconnectOnDiscovery = newValue
	})
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
					.tint(.accentColor)
					Text("PKI based node administration, requires firmware version 2.5+")
						.foregroundStyle(.secondary)
						.font(.caption)
					Toggle(isOn: $usageDataAndCrashReporting) {
						Label("Usage and Crash Data", systemImage: "pencil.and.list.clipboard")
					}
					.tint(.accentColor)
					Text("Provide anonymous usage statistics and crash reports.")
						.foregroundStyle(.secondary)
						.font(.caption)
					if showAutoConnect {
						Toggle(isOn: autoconnectBinding) {
							Label("Automatically Connect", systemImage: "app.connected.to.app.below.fill")
						}
						.tint(.accentColor)
					}
#if targetEnvironment(macCatalyst)
					// App Icon Picker is disabled on macOS Catalyst
#else
					Button {
						isPresentingAppIconSheet.toggle()
					} label: {
						Label("App Icon", systemImage: "app")
					}
					.sheet(isPresented: $isPresentingAppIconSheet) {
						AppIconPicker(isPresenting: self.$isPresentingAppIconSheet)
							.presentationDetents([.medium])
					}
#endif
				}
				Section(header: Text("environment")) {
					VStack(alignment: .leading) {
						Toggle(isOn: $environmentEnableWeatherKit) {
							Label("Weather Conditions", systemImage: "cloud.sun")
						}
						.tint(.accentColor)
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
#if DEBUG
						showAutoConnect = true
#else
						if Bundle.main.isTestFlight {
							showAutoConnect = true
						}
#endif
					}
					.onChange(of: usageDataAndCrashReporting) { oldUsageDataAndCrashReporting, newUsageDataAndCrashReporting in
						if !newUsageDataAndCrashReporting {
							Datadog.set(trackingConsent: .notGranted)
						}
					}
					.onChange(of: purgeStaleNodes) { _, newValue in
						purgeStaleNodeDays = purgeStaleNodeDays > 0 ? purgeStaleNodeDays : 7
						purgeStaleNodeDays = newValue ? purgeStaleNodeDays : 0
						Logger.services.info("ℹ️ Purge Stale Nodes changed to \(purgeStaleNodeDays)")
					}
					.tint(.accentColor)

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
						Text("Favorited and ignored nodes are always retained. Other nodes are cleared from the app database on the schedule set by the user. (Nodes with PKC keys are always retained for at least 7 days.) This feature only purges nodes from the app that are not stored in the device node database.")
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
							Task {
								try await accessoryManager.disconnect()
							}
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
							clearNotifications()
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
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
	}
}
