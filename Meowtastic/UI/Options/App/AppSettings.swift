import Combine
import FirebaseAnalytics
import Foundation
import MapKit
import OSLog
import SwiftProtobuf
import SwiftUI

struct AppSettings: View {
	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var isPresentingCoreDataResetConfirm = false
	@State
	private var isPresentingDeleteMapTilesConfirm = false

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
				}

				Section(header: Text("App Data")) {
					Button {
						isPresentingCoreDataResetConfirm = true
					} label: {
						Label("clear.app.data", systemImage: "trash")
							.foregroundColor(.red)
					}
					.confirmationDialog(
						"are.you.sure",
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
							UserDefaults.standard.reset()
						}
					}
				}
			}
		}
		.navigationTitle("App Settings")
		.navigationBarItems(
			trailing: ConnectedDevice()
		)
		.onAppear {
			Analytics.logEvent(AnalyticEvents.optionsAppSettings.id, parameters: [:])
		}
	}
}
