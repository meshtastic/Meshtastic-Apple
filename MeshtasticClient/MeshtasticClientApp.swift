import SwiftUI

@main
struct MeshtasticClientApp: App {

    @ObservedObject private var bleManager: BLEManager = BLEManager()
	@ObservedObject private var userSettings: UserSettings = UserSettings()
	//let persistenceController = PersistenceController.shared
	@Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
		ContentView()
			.environmentObject(bleManager)
			.environmentObject(userSettings)
			//.environment(\.managedObjectContext, persistenceController.container.viewContext)
		}
		.onChange(of: scenePhase) { (newScenePhase) in
			switch newScenePhase {
			case .background:
				print("Scene is in the background")
				//persistenceController.save()
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
