import SwiftUI
import CoreData

@main
struct MeshtasticClientApp: App {
	
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
