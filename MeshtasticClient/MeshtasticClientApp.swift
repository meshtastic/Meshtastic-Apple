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
			.environmentObject(userSettings)
			.environmentObject(bleManager)
		}
		.onChange(of: scenePhase) { (newScenePhase) in
			switch newScenePhase {
			case .background:
				print("Scene is in the background")
			case .inactive:
				print("Scene is inactive")
			case .active:
				print("Scene is active")
			@unknown default:
				print("Apple must have changed something")
			}
		}
    }
}
