import Foundation
import Combine
import SwiftUI
import SwiftProtobuf
import MapKit
import OSLog

struct AppSettings: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@ObservedObject var tileManager = OfflineTileManager.shared
	@State var totalDownloadedTileSize = ""
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var isPresentingDeleteMapTilesConfirm = false
	@AppStorage("environmentIncludeIAQ") private var environmentIncludeIAQ: Bool = true
	@State private var environmentIncludeWind = false
	@State private var environmentEnableWeatherKit = true
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
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
				Section(header: Text("environment")) {
					if true { //connectedNode?.hasEnvironmentMetrics ?? false {
						VStack(alignment: .leading) {
							Toggle(isOn: $environmentIncludeIAQ) {
								Label("Indoor Air Quality Index", systemImage: "aqi.low")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						}
						VStack(alignment: .leading) {
							Toggle(isOn: $environmentIncludeWind) {
								Label("Wind", systemImage: "wind")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						}
					}
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
				if totalDownloadedTileSize != "0MB" {
					Section(header: Text("Map Tile Data")) {
						Button {
							isPresentingDeleteMapTilesConfirm = true
						} label: {
							Label("\("map.tiles.delete".localized) (\(totalDownloadedTileSize))", systemImage: "trash")
								.foregroundColor(.red)
						}
						.confirmationDialog(
							"are.you.sure",
							isPresented: $isPresentingDeleteMapTilesConfirm,
							titleVisibility: .visible
						) {
							Button("Delete all map tiles?", role: .destructive) {
								tileManager.removeAll()
								totalDownloadedTileSize = tileManager.getAllDownloadedSize()
								Logger.services.debug("delete all tiles")
							}
						}
					}
				}
			}
			.onAppear(perform: {
				totalDownloadedTileSize = tileManager.getAllDownloadedSize()
			})
		}
		.navigationTitle("appsettings")
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		}
	}
}
