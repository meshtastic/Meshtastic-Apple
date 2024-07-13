import SwiftUI
import CoreData
import OSLog

@main
struct MeowtasticApp: App {
	@UIApplicationDelegateAdaptor(MeowtasticAppDelegate.self)
	var appDelegate
	@Environment(\.scenePhase)
	var scenePhase
	@State
	var saveChannels = false
	@State
	var incomingUrl: URL?
	@State
	var channelSettings: String?
	@State
	var addChannels = false
	@StateObject
	var appState = AppState.shared

	@ObservedObject
	private var bleManager: BLEManager = BLEManager.shared

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(\.managedObjectContext, Persistence.shared.viewContext)
				.environmentObject(bleManager)
				.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
					Logger.mesh.debug("URL received \(userActivity)")

					incomingUrl = userActivity.webpageURL

					if (self.incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/#")) != nil {
						if let components = incomingUrl?.absoluteString.components(separatedBy: "#") {
							addChannels = Bool(incomingUrl?["add"] ?? "false") ?? false
							if (incomingUrl?.absoluteString.lowercased().contains("?") != nil) {
								guard let cs = components.last!.components(separatedBy: "?").first else {
									return
								}

								channelSettings = cs
							} else {
								guard let cs = components.first else {
									return
								}

								channelSettings = cs
							}

							Logger.services.debug("Add Channel \(addChannels)")
						}
						self.saveChannels = true
						Logger.mesh.debug("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
					}
					if self.saveChannels {
						Logger.mesh.debug("User wants to open Channel Settings URL: \(String(describing: self.incomingUrl!.relativeString))")
					}
				}
				.onOpenURL(perform: { (url) in
					Logger.mesh.debug("Some sort of URL was received \(url)")

					self.incomingUrl = url

					if url.absoluteString.lowercased().contains("meshtastic.org/e/#") {
						if let components = self.incomingUrl?.absoluteString.components(separatedBy: "#") {
							addChannels = Bool(self.incomingUrl?["add"] ?? "false") ?? false

							if (incomingUrl?.absoluteString.lowercased().contains("?") != nil) {
								guard let cs = components.last!.components(separatedBy: "?").first else {
									return
								}
								self.channelSettings = cs
							} else {
								guard let cs = components.first else {
									return
								}
								channelSettings = cs
							}
							Logger.services.debug("Add Channel \(addChannels)")
						}
						self.saveChannels = true
						Logger.mesh.debug("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
					} else if url.absoluteString.lowercased().contains("meshtastic://") {
						appState.navigationPath = url.absoluteString

						let path = appState.navigationPath ?? ""
						if path.starts(with: "meshtastic://map") {
							AppState.shared.tabSelection = Tab.map
						} else if path.starts(with: "meshtastic://nodes") {
							AppState.shared.tabSelection = Tab.nodes
						}

					} else {
						saveChannels = false
						Logger.mesh.debug("User wants to import a MBTILES offline map file: \(incomingUrl?.absoluteString ?? "No Tiles link")")
					}

					/// Only do the map tiles stuff if it is enabled
					if UserDefaults.enableOfflineMapsMBTiles {
						/// we are expecting a .mbtiles map file that contains raster data
						/// save it to the documents directory, and name it offline_map.mbtiles
						let fileManager = FileManager.default
						let documentsDirectory = fileManager.urls(
							for: .documentDirectory,
							in: .userDomainMask
						)
							.first!
						let destination = documentsDirectory.appendingPathComponent(
							"offline_map.mbtiles",
							isDirectory: false
						)

						if !self.saveChannels {
							// tell the system we want the file please
							guard url.startAccessingSecurityScopedResource() else {
								return
							}

							// do we need to delete an old one?
							if fileManager.fileExists(atPath: destination.path) {
								Logger.mesh.info("Found an old map file.  Deleting it")
								try? fileManager.removeItem(atPath: destination.path)
							}

							do {
								try fileManager.copyItem(at: url, to: destination)
							} catch {
								Logger.mesh.error("Copy MB Tile file failed. Error: \(error.localizedDescription)")
							}

							if fileManager.fileExists(atPath: destination.path) {
								Logger.mesh.info("Saved the map file")

								// need to tell the map view that it needs to update and try loading the new overlay
								UserDefaults.standard.set(
									Date().timeIntervalSince1970,
									forKey: "lastUpdatedLocalMapFile"
								)
							} else {
								Logger.mesh.error("Didn't save the map file")
							}
						}
					}
				})
				.sheet(isPresented: $saveChannels) {
					SaveChannelQRCode(
						channelSetLink: channelSettings ?? "Empty Channel URL",
						addChannels: addChannels,
						bleManager: bleManager
					)
					.presentationDetents([.large])
					.presentationDragIndicator(.visible)
				}
		}
		.onChange(of: scenePhase, initial: false) {
			if scenePhase == .background {
				try? Persistence.shared.viewContext.save()
			}
		}
	}
}
