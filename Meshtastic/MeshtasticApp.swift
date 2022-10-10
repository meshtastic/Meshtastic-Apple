// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import CoreData

@main
struct MeshtasticAppleApp: App {
	
	let persistenceController = PersistenceController.shared

	@ObservedObject private var bleManager: BLEManager = BLEManager.shared
	@ObservedObject private var userSettings: UserSettings = UserSettings()

	@State var saveChannels = false
	@State var incomingUrl: URL?
	@State var channelSettings: String?
	
	@Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
		ContentView()
			.environment(\.managedObjectContext, persistenceController.container.viewContext)
			.environmentObject(bleManager)
			.environmentObject(userSettings)

			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in

				print("URL received \(userActivity)")
				incomingUrl = userActivity.webpageURL
				
				if incomingUrl!.absoluteString.lowercased().contains("meshtastic.org/e/#") {
					
					if let components = incomingUrl?.absoluteString.components(separatedBy: "#") {
					   channelSettings = components.last!
					}
					saveChannels = true
					print("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
				}
				if saveChannels {
					print("User wants to open Channel Settings URL: \(String(describing: incomingUrl!.relativeString))")
				}
			}
			.sheet(isPresented: $saveChannels) {
				
				let channelSettingsString = incomingUrl?.absoluteString
				SaveChannelQRCode(channelHash: channelSettings ?? "Empty Channel URL")
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.visible)
			}
			.onOpenURL(perform: { (url) in
				
				print("Some sort of URL was received \(url)")
				incomingUrl = url
				
				if url.absoluteString.lowercased().contains("meshtastic.org/e/#") {
					if let components = incomingUrl?.absoluteString.components(separatedBy: "#") {
					   channelSettings = components.last!
					}
					saveChannels = true
					print("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
				} else {
					print("User wants to import a MBTILES offline map file: \(incomingUrl?.absoluteString ?? "No Tiles link")")
				}

				//we are expecting a .mbtiles map file that contains raster data
				//save it to the documents directory, and name it offline_map.mbtiles
				let fileManager = FileManager.default
				let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
				let destination = documentsDirectory.appendingPathComponent("offline_map.mbtiles", isDirectory: false)
				
				//do we need to delete an old one?
				if (fileManager.fileExists(atPath: destination.path)) {
					print("ℹ️ Found an old map file.  Deleting it")
					try? fileManager.removeItem(atPath: destination.path)
				}
				
				do {
					try fileManager.copyItem(at: url, to: destination)
				} catch {
					print("Copy MB Tile file failed. Error: \(error)")
				}
				
				if (fileManager.fileExists(atPath: destination.path)) {
					print("ℹ️ Saved the map file")
					
					//need to tell the map view that it needs to update and try loading the new overlay
					UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdatedLocalMapFile")
					
				} else {
					print("💥 Didn't save the map file")
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
