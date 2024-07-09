// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import CoreData
import OSLog
#if canImport(TipKit)
import TipKit
#endif

@available(iOS 17.0, *)
@main
struct MeshtasticAppleApp: App {

	@UIApplicationDelegateAdaptor(MeshtasticAppDelegate.self) var appDelegate
	let persistenceController = PersistenceController.shared
	@ObservedObject private var bleManager: BLEManager = BLEManager.shared

	@Environment(\.scenePhase) var scenePhase

	@State var saveChannels = false
	@State var incomingUrl: URL?
	@State var channelSettings: String?
	@State var addChannels = false
	@StateObject var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
			ContentView()
			.environment(\.managedObjectContext, persistenceController.container.viewContext)
			.environmentObject(bleManager)
			.sheet(isPresented: $saveChannels) {
				SaveChannelQRCode(channelSetLink: channelSettings ?? "Empty Channel URL", addChannels: addChannels, bleManager: bleManager)
					.presentationDetents([.large])
					.presentationDragIndicator(.visible)
			}
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in

				Logger.mesh.debug("URL received \(userActivity)")
				self.incomingUrl = userActivity.webpageURL

				if (self.incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/#")) != nil {
					if let components = self.incomingUrl?.absoluteString.components(separatedBy: "#") {
						self.addChannels = Bool(self.incomingUrl?["add"] ?? "false") ?? false
						if ((self.incomingUrl?.absoluteString.lowercased().contains("?")) != nil) {
							guard let cs = components.last!.components(separatedBy: "?").first else {
								return
							}
							self.channelSettings = cs
						} else {
							guard let cs = components.first else {
								return
							}
							self.channelSettings = cs
						}
						Logger.services.debug("Add Channel \(self.addChannels)")
					}
					self.saveChannels = true
					Logger.mesh.debug("User wants to open a Channel Settings URL: \(self.incomingUrl?.absoluteString ?? "No QR Code Link")")
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
						self.channelSettings = components.last!
					}
					self.saveChannels = true
					Logger.mesh.debug("User wants to open a Channel Settings URL: \(self.incomingUrl?.absoluteString ?? "No QR Code Link")")
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
					Logger.mesh.debug("User wants to import a MBTILES offline map file: \(self.incomingUrl?.absoluteString ?? "No Tiles link")")
				}

				/// Only do the map tiles stuff if it is enabled
				if UserDefaults.enableOfflineMapsMBTiles {
					/// we are expecting a .mbtiles map file that contains raster data
					/// save it to the documents directory, and name it offline_map.mbtiles
					let fileManager = FileManager.default
					let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
					let destination = documentsDirectory.appendingPathComponent("offline_map.mbtiles", isDirectory: false)

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
							UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdatedLocalMapFile")

						} else {
							Logger.mesh.error("Didn't save the map file")
						}
					}
				}
			})
			.task {
				if #available(iOS 17.0, macOS 14.0, *) {
					#if DEBUG
					/// Optionally, call `Tips.resetDatastore()` before `Tips.configure()` to reset the state of all tips. This will allow tips to re-appear even after they have been dismissed by the user.
					/// This is for testing only, and should not be enabled in release builds.
					try? Tips.resetDatastore()
					#endif

					try? Tips.configure(
						[
							// Reset which tips have been shown and what parameters have been tracked, useful during testing and for this sample project
							.datastoreLocation(.applicationDefault),
							// When should the tips be presented? If you use .immediate, they'll all be presented whenever a screen with a tip appears.
							// You can adjust this on per tip level as well
							.displayFrequency(.immediate)
						]
					)
				}
			}
		}
		.onChange(of: scenePhase) { (newScenePhase) in
			switch newScenePhase {
			case .background:
				Logger.services.info("🎬 [App] Scene is in the background")
				do {

					try persistenceController.container.viewContext.save()
					Logger.services.info("💾 [App] Saved CoreData ViewContext when the app went to the background.")

				} catch {

					Logger.services.error("💥 [App] Failed to save viewContext when the app goes to the background.")
				}
			case .inactive:
				Logger.services.info("🎬 [App] Scene is inactive")
			case .active:
				Logger.services.info("🎬 [App] Scene is active")
			@unknown default:
				Logger.services.error("🍎 [App] Apple must have changed something")
			}
		}
	}
}

class AppState: ObservableObject {
	static let shared = AppState()

	@Published var tabSelection: Tab = .ble
	@Published var unreadDirectMessages: Int = 0
	@Published var unreadChannelMessages: Int = 0
	@Published var firmwareVersion: String = "0.0.0"
	@Published var navigationPath: String?
}
