// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import CoreData

@main
struct MeshtasticAppleApp: App {
	
	let persistenceController = PersistenceController.shared

	@ObservedObject private var bleManager: BLEManager = BLEManager.shared
	@ObservedObject private var userSettings: UserSettings = UserSettings()

	@State var saveQR = false
	@State var channelUrl: URL?
	
	@Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
		ContentView()
			.environment(\.managedObjectContext, persistenceController.container.viewContext)
			.environmentObject(bleManager)
			.environmentObject(userSettings)

			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in

				print("QR Code URL received from the Camera \(userActivity)")
				channelUrl = userActivity.webpageURL
				if channelUrl!.absoluteString.lowercased().contains("https://meshtastic.org/e/#") {
					saveQR = true
				}
				
				print("User wants to open URL: \(String(describing: channelUrl?.relativeString))")

			}
			.sheet(isPresented: $saveQR) {
				
				SaveChannelQRCode(channelHash: channelUrl?.absoluteString ?? "Empty Channel URL")
			}
			.onOpenURL(perform: { (url) in
				
				print("Some sort of URL was received \(url)")
				channelUrl = url
				
				
				if url.absoluteString.lowercased().contains("https://meshtastic.org/e/#") {
					saveQR = true
					print("User wants to open a Channel Settings URL: \(channelUrl?.absoluteString ?? "No QR Code Link")")
				} else {
					print("User wants to import a MBTILES offline map file: \(channelUrl?.absoluteString ?? "No Tiles link")")
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
