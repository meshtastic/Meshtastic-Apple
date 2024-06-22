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
	@StateObject var locationHelper = LocationHelper()
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var isPresentingDeleteMapTilesConfirm = false
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
				Section(header: Text("phone.gps")) {
					if #available(iOS 17.0, macOS 14.0, *) {
						GPSStatus()
					} else {
						let accuracy = Measurement(value: locationHelper.locationManager.location?.horizontalAccuracy ?? 300, unit: UnitLength.meters)
						let altitiude = Measurement(value: locationHelper.locationManager.location?.altitude ?? 0, unit: UnitLength.meters)
						let speed = Measurement(value: locationHelper.locationManager.location?.speed ?? 0, unit: UnitSpeed.kilometersPerHour)
						HStack {
							Label("Accuracy \(accuracy.formatted())", systemImage: "scope")
								.font(.footnote)
							Label("Sats \(LocationHelper.satsInView)", systemImage: "sparkles")
								.font(.footnote)
						}
						Label("Coordinate \(String(format: "%.5f", locationHelper.locationManager.location?.coordinate.latitude ?? 0)), \(String(format: "%.5f", locationHelper.locationManager.location?.coordinate.longitude ?? 0))", systemImage: "mappin")
							.font(.footnote)
							.textSelection(.enabled)
						if locationHelper.locationManager.location?.verticalAccuracy ?? 0 > 0 {
							Label("Altitude \(altitiude.formatted())", systemImage: "mountain.2")
								.font(.footnote)
						}
						if locationHelper.locationManager.location?.courseAccuracy ?? 0 > 0 {
							let degrees = Angle.degrees(locationHelper.locationManager.location?.course ?? 0)
							Label {
								let heading = Measurement(value: degrees.degrees, unit: UnitAngle.degrees)
								Text("Heading: \(heading.formatted(.measurement(width: .narrow)))")
							} icon: {
								Image(systemName: "location.north")
									.symbolRenderingMode(.hierarchical)
									.rotationEffect(degrees)
							}
							.font(.footnote)
						}
						if locationHelper.locationManager.location?.speedAccuracy ?? 0 > 0 {
							Label("Speed \(speed.formatted())", systemImage: "speedometer")
								.font(.footnote)
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
								url = url.appendingPathComponent("backups").appendingPathComponent(String(UserDefaults.preferredPeripheralNum))
								do {
									try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite"))
									/// Delete -shm file
									do {
										try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite-wal"))
										do {
											try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite-shm"))
										} catch {
											print(error)
										}
									} catch {
										print(error)
									}
								} catch {
									print(error)
								}
							}
							clearCoreDataDatabase(context: context, includeRoutes: true)
							context.reset()
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
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		}
	}
}
