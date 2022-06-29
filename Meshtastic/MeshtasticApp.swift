// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import CoreData

@main
struct MeshtasticAppleApp: App {
	
	let persistenceController = PersistenceController.shared

	@ObservedObject private var bleManager: BLEManager = BLEManager.shared
	@ObservedObject private var userSettings: UserSettings = UserSettings()

	@Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
		ContentView()
			.environment(\.managedObjectContext, persistenceController.container.viewContext)
			.environmentObject(bleManager)
			.environmentObject(userSettings)
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
				  
				  print("Continue activity \(userActivity)")
				  guard let url = userActivity.webpageURL else {
					  return
				  }
				  
				  print("User wants to open URL: \(url)")
				  // TODO same handling as done in onOpenURL()

			}
			.onOpenURL(perform: { (url) in
				
				print("URL OPENED")
				print(url) 
				
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
				
				try? fileManager.copyItem(at: url, to: destination)
				
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
