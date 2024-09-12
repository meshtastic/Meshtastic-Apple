import BackgroundTasks
import CoreBluetooth
import CoreData
import FirebaseAnalytics
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
	private var nodeConfig: NodeConfig
	@ObservedObject
	private var locationManager: LocationManager

	@ViewBuilder
	var body: some Scene {
		WindowGroup {
			Content()
				.environment(\.managedObjectContext, persistence.viewContext)
				.environmentObject(bleManager)
				.environmentObject(nodeConfig)
				.environmentObject(locationManager)
				.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
					Logger.mesh.debug("URL received \(userActivity)")

					incomingUrl = userActivity.webpageURL

					if
						incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/#") != nil,
						let components = incomingUrl?.absoluteString.components(separatedBy: "#")
					{
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
				}
				.onOpenURL { url in
					Logger.mesh.debug("Some sort of URL was received \(url)")

					incomingUrl = url

					if url.absoluteString.lowercased().contains("meshtastic.org/e/#") {
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

						Logger.mesh.debug(
							"User wants to open a Channel Config: \(incomingUrl?.absoluteString ?? "No QR Code Link")"
						)
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
				try? Persistence.shared.container.viewContext.save()

				scheduleAppRefresh()
			}
		}
		.backgroundTask(.appRefresh(AppConstants.backgroundTaskID)) {
			Logger.app.debug("Background task started")

			await refreshApp()
		}
	}

	init() {
		self.persistence = Persistence.shared.container
		self.locationManager = LocationManager.shared

		let appState = AppState()
		let bleManager = BLEManager(
			appState: appState,
			context: persistence.viewContext
		)
		let nodeConfig = NodeConfig(
			bleManager: bleManager,
			context: persistence.viewContext
		)

		self.appState = appState
		self.bleManager = bleManager
		self.nodeConfig = nodeConfig
	}

	private func scheduleAppRefresh() {
		let request = BGAppRefreshTaskRequest(identifier: AppConstants.backgroundTaskID)
		request.earliestBeginDate = Calendar.current.date(byAdding: .minute, value: 10, to: .now)

		try? BGTaskScheduler.shared.submit(request)

		Logger.app.debug("Background task scheduled")
	}

	private func refreshApp() async {
		Analytics.logEvent(AnalyticEvents.backgroundUpdate.id, parameters: nil)

		guard !bleManager.isSubscribed else {
			return
		}

		bleManager.devicesDelegate = self
		bleManager.startScanning()
	}
}

extension Meowtastic: DevicesDelegate {
	func onChange(devices: [Device]) {
		let device = devices.first(where: { device in
			device.peripheral.state != CBPeripheralState.connected
			&& device.peripheral.state != CBPeripheralState.connecting
			&& device.peripheral.identifier.uuidString == UserDefaults.preferredPeripheralId
		})

		guard let device else {
			return
		}

		bleManager.stopScanning()
		bleManager.connectTo(peripheral: device.peripheral)
	}
}
