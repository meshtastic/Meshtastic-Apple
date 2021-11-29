import SwiftUI
import CoreData

@main
struct MeshtasticClientApp: App {

    @ObservedObject private var bleManager: BLEManager = BLEManager()
	@ObservedObject private var userSettings: UserSettings = UserSettings()
	
	@Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
		ContentView()
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
	
	var persistentContainer: NSPersistentContainer = {
		   let container = NSPersistentContainer(name: "Mesh")
		   container.loadPersistentStores(completionHandler: { (storeDescription, error) in
			   if let error = error as NSError? {
				   fatalError("Unresolved error \(error), \(error.userInfo)")
			   }
		   })
		   return container
	   }()
	
	func saveContext() {
		   let context = persistentContainer.viewContext
		   if context.hasChanges {
			   do {
				   try context.save()
			   } catch {
				   let nserror = error as NSError
				   fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
			   }
		   }
	   }
}
