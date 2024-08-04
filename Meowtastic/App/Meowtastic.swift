import CoreData
import OSLog
import SwiftUI

@main
struct Meowtastic: App {
	private let persistence: NSPersistentContainer

	@UIApplicationDelegateAdaptor(MeowtasticDelegate.self)
	var appDelegate
	@Environment(\.scenePhase)
	var scenePhase
	@State
	var incomingUrl: URL?
	@State
	var channelSettings: String?
	@State
	var addChannels = false

	@ObservedObject
	private var appState: AppState
	@ObservedObject
	private var bleManager: BLEManager
	@ObservedObject
	private var locationManager: LocationManager

	@ViewBuilder
	var body: some Scene {
		WindowGroup {
			Content()
				.environment(\.managedObjectContext, persistence.viewContext)
				.environmentObject(bleManager)
				.environmentObject(locationManager)
				.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
					Logger.mesh.debug("URL received \(userActivity)")

					incomingUrl = userActivity.webpageURL

					if incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/#") != nil {
						if let components = incomingUrl?.absoluteString.components(separatedBy: "#") {
							addChannels = Bool(incomingUrl?["add"] ?? "false") ?? false

							if incomingUrl?.absoluteString.lowercased().contains("?") != nil {
								guard let cs = components.last?.components(separatedBy: "?").first else {
									return
								}

								channelSettings = cs
							}
							else {
								guard let cs = components.first else {
									return
								}

								channelSettings = cs
							}

							Logger.services.debug("Add Channel \(addChannels)")
						}

						Logger.mesh.debug("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
					}
				}
				.onOpenURL { url in
					Logger.mesh.debug("Some sort of URL was received \(url)")

					incomingUrl = url

					if url.absoluteString.lowercased().contains("meshtastic.org/e/#") {
						if let components = incomingUrl?.absoluteString.components(separatedBy: "#") {
							addChannels = Bool(incomingUrl?["add"] ?? "false") ?? false

							if incomingUrl?.absoluteString.lowercased().contains("?") != nil {
								guard let cs = components.last!.components(separatedBy: "?").first else {
									return
								}
								self.channelSettings = cs
							}
							else {
								guard let cs = components.first else {
									return
								}
								channelSettings = cs
							}
							Logger.services.debug("Add Channel \(addChannels)")
						}
						Logger.mesh.debug("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
					}
					else if url.absoluteString.lowercased().contains("meshtastic:///") {
						appState.navigationPath = url.absoluteString

						let path = appState.navigationPath ?? ""
						if path.starts(with: "meshtastic:///map") {
							AppState.shared.tabSelection = TabTag.map
						}
						else if path.starts(with: "meshtastic:///nodes") {
							AppState.shared.tabSelection = TabTag.nodes
						}

					}
				}
		}
		.onChange(of: scenePhase, initial: false) {
			if scenePhase == .background {
				try? Persistence.shared.viewContext.save()
			}
		}
	}

	init() {
		self.persistence = Persistence.shared
		self.locationManager = LocationManager.shared

		let appState = AppState()
		self.appState = appState

		self.bleManager = BLEManager(
			appState: appState,
			context: persistence.viewContext
		)
	}
}
