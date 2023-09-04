// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import CoreData

@main
struct MeshtasticAppleApp: App {
	@UIApplicationDelegateAdaptor(MeshtasticAppDelegate.self) var appDelegate
	let persistenceController = PersistenceController.shared
	@ObservedObject private var bleManager: BLEManager = BLEManager()
	@Environment(\.scenePhase) var scenePhase

	@State var saveChannels = false
	@State var incomingUrl: URL?
	@State var channelSettings: String?
	@StateObject var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
			ContentView()
			.environment(\.managedObjectContext, persistenceController.container.viewContext)
			.environmentObject(bleManager)
			.sheet(isPresented: $saveChannels) {
				SaveChannelQRCode(channelSetLink: channelSettings ?? "Empty Channel URL", bleManager: bleManager)
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.visible)
			}
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in

				print("URL received \(userActivity)")
				self.incomingUrl = userActivity.webpageURL

				if (self.incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/#")) != nil {

					if let components = self.incomingUrl?.absoluteString.components(separatedBy: "#") {
						self.channelSettings = components.last!
					}
					self.saveChannels = true
					print("User wants to open a Channel Settings URL: \(self.incomingUrl?.absoluteString ?? "No QR Code Link")")
				}
				if self.saveChannels {
					print("User wants to open Channel Settings URL: \(String(describing: self.incomingUrl!.relativeString))")
				}
			}
			.onOpenURL(perform: { (url) in

				print("Some sort of URL was received \(url)")
				self.incomingUrl = url
				if url.absoluteString.lowercased().contains("meshtastic.org/e/#") {
					if let components = self.incomingUrl?.absoluteString.components(separatedBy: "#") {
						self.channelSettings = components.last!
					}
					self.saveChannels = true
					print("User wants to open a Channel Settings URL: \(self.incomingUrl?.absoluteString ?? "No QR Code Link")")
				} else {
					saveChannels = false
					print("User wants to import a MBTILES offline map file: \(self.incomingUrl?.absoluteString ?? "No Tiles link")")
				}

				// we are expecting a .mbtiles map file that contains raster data
				// save it to the documents directory, and name it offline_map.mbtiles
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
						print("ℹ️ Found an old map file.  Deleting it")
						try? fileManager.removeItem(atPath: destination.path)
					}

					do {
						try fileManager.copyItem(at: url, to: destination)
					} catch {
						print("Copy MB Tile file failed. Error: \(error)")
					}

					if fileManager.fileExists(atPath: destination.path) {
						print("ℹ️ Saved the map file")

						// need to tell the map view that it needs to update and try loading the new overlay
						UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdatedLocalMapFile")

					} else {
						print("💥 Didn't save the map file")
					}
				}
			})
		}
		.onChange(of: scenePhase) { (newScenePhase) in
			switch newScenePhase {
			case .background:
				print("ℹ️ Scene is in the background")
				do {

					try persistenceController.container.viewContext.save()
					print("💾 Saved CoreData ViewContext when the app went to the background.")

				} catch {

					print("💥 Failed to save viewContext when the app goes to the background.")
				}
			case .inactive:
				print("ℹ️ Scene is inactive")
			case .active:
				print("ℹ️ Scene is active")
			@unknown default:
				print("💥 Apple must have changed something")
			}
		}
	}
}

class AppState: ObservableObject {
	static let shared = AppState()

	@Published var tabSelection: Tab = .ble
	@Published var unreadDirectMessages: Int = 0
	@Published var unreadChannelMessages: Int = 0
	@Published var connectedNode: NodeInfoEntity?
}
