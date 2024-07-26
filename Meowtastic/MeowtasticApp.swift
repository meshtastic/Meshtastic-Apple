import SwiftUI
import CoreData
import OSLog

@main
struct MeowtasticApp: App {
	private let persistence: NSPersistentContainer

	@UIApplicationDelegateAdaptor(MeowtasticAppDelegate.self)
	var appDelegate
	@Environment(\.scenePhase)
	var scenePhase
	@State
	var saveChannels = false
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

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(\.managedObjectContext, persistence.viewContext)
				.environmentObject(bleManager)
				.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
					Logger.mesh.debug("URL received \(userActivity)")

					incomingUrl = userActivity.webpageURL

					if incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/#") != nil {
						if let components = incomingUrl?.absoluteString.components(separatedBy: "#") {
							addChannels = Bool(incomingUrl?["add"] ?? "false") ?? false

							if incomingUrl?.absoluteString.lowercased().contains("?") != nil {
								guard let cs = components.last!.components(separatedBy: "?").first else {
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

						self.saveChannels = true
						Logger.mesh.debug("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
					}

					if self.saveChannels {
						Logger.mesh.debug("User wants to open Channel Settings URL: \(String(describing: self.incomingUrl!.relativeString))")
					}
				}
				.onOpenURL { url in
					Logger.mesh.debug("Some sort of URL was received \(url)")

					self.incomingUrl = url

					if url.absoluteString.lowercased().contains("meshtastic.org/e/#") {
						if let components = self.incomingUrl?.absoluteString.components(separatedBy: "#") {
							addChannels = Bool(self.incomingUrl?["add"] ?? "false") ?? false

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
						self.saveChannels = true
						Logger.mesh.debug("User wants to open a Channel Settings URL: \(incomingUrl?.absoluteString ?? "No QR Code Link")")
					} else if url.absoluteString.lowercased().contains("meshtastic:///") {
						appState.navigationPath = url.absoluteString

						let path = appState.navigationPath ?? ""
						if path.starts(with: "meshtastic:///map") {
							AppState.shared.tabSelection = Tab.map
						} else if path.starts(with: "meshtastic:///nodes") {
							AppState.shared.tabSelection = Tab.nodes
						}

					} else {
						saveChannels = false
						Logger.mesh.debug("User wants to import a MBTILES offline map file: \(incomingUrl?.absoluteString ?? "No Tiles link")")
					}

				}
				.sheet(isPresented: $saveChannels) {
					SaveChannelQRCode(
						channelSetLink: channelSettings ?? "Empty Channel URL",
						addChannels: addChannels,
						bleManager: bleManager
					)
					.presentationDetents([.large])
					.presentationDragIndicator(.visible)
				}
		}
		.onChange(of: scenePhase, initial: false) {
			if scenePhase == .background {
				try? Persistence.shared.viewContext.save()
			}
		}
	}

	init() {
		let persistence = Persistence.shared
		self.persistence = persistence

		let appState = AppState()
		self.appState = appState

		let bleManager = BLEManager(
			appState: appState,
			context: persistence.viewContext
		)
		self.bleManager = bleManager
	}
}
