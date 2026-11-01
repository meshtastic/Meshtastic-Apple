import CoreBluetooth
import Intents
import OSLog
import SwiftUI
import Foundation
import MapKit

struct DeviceOnboarding: View {
	enum SetupGuide: Hashable {
		case welcome
		case notifications
		case location
		case bluetooth
		case localNetwork
		case siri

		/// Screen name reported to RUM. See `ScreenName`.
		var screenName: ScreenName {
			switch self {
			case .welcome: return .onboardingWelcome
			case .notifications: return .onboardingNotifications
			case .location: return .onboardingLocation
			case .bluetooth: return .onboardingBluetooth
			case .localNetwork: return .onboardingLocalNetwork
			case .siri: return .onboardingSiri
			}
		}
	}

	@EnvironmentObject var accessoryManager: AccessoryManager
	@ObservedObject private var locationsHandler: LocationsHandler = .shared
	@State var navigationPath: [SetupGuide] = []
	@State var locationStatus = LocationsHandler.shared.manager.authorizationStatus
	@AppStorage("provideLocation") private var provideLocation: Bool = false
	@AppStorage("provideLocationInterval") private var provideLocationInterval: Int = 30
	@AppStorage("channelMessageNotifications") private var channelMessageNotifications: Bool = true
	@AppStorage("newNodeNotifications") private var newNodeNotifications: Bool = false
	@AppStorage("lowBatteryNotifications") private var lowBatteryNotifications: Bool = false
	@Environment(\.dismiss) var dismiss

	private var newNodeNotificationsBinding: Binding<Bool> {
		Binding(
			get: { newNodeNotifications },
			set: { value in
				let updated = EventFirmwareNotificationPolicy.userUpdatedSettings(
					newNodeNotifications: value,
					isEventFirmware: accessoryManager.firmwareEdition.isEvent
				)
				newNodeNotifications = updated.newNodeNotifications
				UserDefaults.nodeNotificationsAutoDisabledForEvent = updated.autoDisabledForEvent
				UserDefaults.nodeNotificationsUserOverrideForEvent = updated.userOverrideForEvent
			}
		)
	}

	var welcomeView: some View {
		OnboardingPage(
			title: String(localized: "Welcome to Meshtastic"),
			footer: String(localized: "Meshtastic does not collect any personal information. We do anonymously collect usage and crash data to improve the app."),
			buttonTitle: String(localized: "Get started"),
			action: { await goToNextStep(after: .welcome) }
		) {
			OnboardingFeatureRow(
				symbol: "antenna.radiowaves.left.and.right",
				color: .green,
				title: String(localized: "Off-Grid Messaging"),
				text: String(localized: "Send text, positions and more over LoRa radios. No cell service or internet needed.")
			)
			OnboardingFeatureRow(
				symbol: "lock.shield",
				title: String(localized: "Privacy First"),
				text: String(localized: "Channels are encrypted. Your radio shares no location until you turn it on. Public channels can be logged by anyone nearby and only ever get an approximate location. Your precise location goes only to private channels you choose.")
			)
			OnboardingFeatureRow(
				symbol: "slider.horizontal.3",
				color: .indigo,
				title: String(localized: "Set Up the Features You Want"),
				text: String(localized: "The next few screens let you choose notifications, location sharing and Siri. Change any of them later in Settings.")
			)
		}
	}

	var notificationView: some View {
		OnboardingPage(
			title: String(localized: "App Notifications"),
			intro: createNotificationsString(),
			action: {
				await requestNotificationsPermissions()
				await goToNextStep(after: .notifications)
			}
		) {
			Text("Send Notifications")
				.font(.title3.bold())
			OnboardingFeatureRow(
				symbol: "message",
				title: String(localized: "Incoming Messages"),
				text: String(localized: "Notifications for channel and direct messages."),
				isOn: $channelMessageNotifications
			)
			OnboardingFeatureRow(
				symbol: "flipphone",
				color: .green,
				title: String(localized: "New Nodes"),
				text: String(localized: "Notifications for newly discovered nodes."),
				isOn: newNodeNotificationsBinding
			)
			OnboardingFeatureRow(
				symbol: "battery.25percent",
				color: .orange,
				title: String(localized: "Low Battery"),
				text: String(localized: "Notifications for low battery alerts for the connected device."),
				isOn: $lowBatteryNotifications
			)
			Text("Critical Alerts")
				.font(.title3.bold())
			OnboardingFeatureRow(
				symbol: "exclamationmark.triangle.fill",
				color: .red,
				text: String(localized: "Select packets sent as critical will ignore the mute switch and Do Not Disturb settings in the OS notification center.")
			)
		}
		.onAppear {
			if UserDefaults.standard.object(forKey: "channelMessageNotifications") == nil {
				channelMessageNotifications = true
			}
			if UserDefaults.standard.object(forKey: "newNodeNotifications") == nil {
				newNodeNotifications = false
			}
			if UserDefaults.standard.object(forKey: "lowBatteryNotifications") == nil {
				lowBatteryNotifications = false
			}
		}
	}

	var locationView: some View {
		OnboardingPage(
			title: String(localized: "Phone Location"),
			intro: createLocationString(),
			action: {
				await requestLocationPermissions()
				await goToNextStep(after: .location)
			}
		) {
			OnboardingFeatureRow(
				symbol: "location",
				title: String(localized: "Share Location"),
				text: String(localized: "Use your phone GPS to send locations to your node to instead of using a hardware GPS on your node."),
				isOn: $provideLocation
			)
			.onChange(of: provideLocation) {
				UserDefaults.provideLocationInterval = 30
				UserDefaults.enableSmartPosition = true
			}
			OnboardingFeatureRow(
				symbol: "location.fill",
				title: String(localized: "Continuous Location Updates"),
				text: String(localized: "Keep the mesh map updated and send your position to the mesh even while using other apps."),
				isOn: $locationsHandler.backgroundActivity
			)
			OnboardingFeatureRow(
				symbol: "lines.measurement.horizontal",
				color: .indigo,
				title: String(localized: "Distance Measurements"),
				text: String(localized: "Display the distance between your phone and other Meshtastic nodes with positions.")
			)
			OnboardingFeatureRow(
				symbol: "line.3.horizontal.decrease.circle",
				color: .orange,
				title: String(localized: "Distance Filters"),
				text: String(localized: "Filter the node list and mesh map based on proximity to your phone.")
			)
			OnboardingFeatureRow(
				symbol: "mappin",
				color: .green,
				title: String(localized: "Mesh Map Location"),
				text: String(localized: "Enables the blue location dot for your phone in the mesh map.")
			)
		}
	}

	var localNetworkView: some View {
		OnboardingPage(
			title: String(localized: "Local Network Access"),
			intro: createLocalNetworkString(),
			action: {
				await requestLocalNetworkPermissions()
				await goToNextStep(after: .localNetwork)
			}
		) {
			OnboardingFeatureRow(
				symbol: "network",
				color: .green,
				title: "Network-based Nodes".localized,
				text: "The Meshtastic App can connect to and manage network-enabled nodes.".localized
			)
			OnboardingFeatureRow(
				symbol: "person.and.background.dotted",
				color: .indigo,
				title: "Background Connections".localized,
				text: "Background network connections are not supported and may disconnect when you leave the app.".localized
			)
			OnboardingFeatureRow(
				symbol: "arrow.trianglehead.2.clockwise",
				color: .orange,
				title: "Minimum Firmware Version".localized,
				text: "For the best connection experience, minimum firmware version 2.7.4 is required.".localized
			)
		}
	}

	var bluetoothView: some View {
		OnboardingPage(
			title: String(localized: "Bluetooth Connectivity"),
			intro: createBluetoothString(),
			action: {
				await requestBluetoothPermissions()
				await goToNextStep(after: .bluetooth)
			}
		) {
			OnboardingFeatureRow(
				symbol: "custom.bluetooth",
				color: .teal,
				title: "Bluetooth Connected Nodes".localized,
				text: "The most reliable messaging experience is with Bluetooth Low Energy connected nodes.".localized
			)
			OnboardingFeatureRow(
				symbol: "person.and.background.dotted",
				color: .indigo,
				title: "Background Connections".localized,
				text: "Bluetooth Low Energy supports background connections. When possible, the application will remain connected to these accessories while the app is in the background.".localized
			)
		}
	}

	var siriView: some View {
		OnboardingPage(
			title: String(localized: "Siri, Shortcuts & CarPlay"),
			intro: createSiriString(),
			action: {
				await requestSiriPermissions()
				await goToNextStep(after: .siri)
			}
		) {
			OnboardingFeatureRow(
				symbol: "car.fill",
				color: .red,
				title: String(localized: "CarPlay Messaging"),
				text: String(localized: "Read and reply to Meshtastic channel and direct messages directly from your car's display using CarPlay.")
			)
			OnboardingFeatureRow(
				symbol: "message",
				title: String(localized: "Send a Group Message"),
				text: String(localized: "\"Send a Meshtastic group message\" — send a message to a mesh channel.")
			)
			OnboardingFeatureRow(
				symbol: "bubble",
				color: .indigo,
				title: String(localized: "Send a Direct Message"),
				text: String(localized: "\"Send a Meshtastic direct message\" — send a private message to a node.")
			)
			OnboardingFeatureRow(
				symbol: "power",
				color: .orange,
				title: String(localized: "Shut Down / Restart Node"),
				text: String(localized: "\"Shut down my Meshtastic node\" or \"Restart my Meshtastic node\".")
			)
			OnboardingFeatureRow(
				symbol: "antenna.radiowaves.left.and.right.slash",
				color: .green,
				title: String(localized: "Disconnect Node"),
				text: String(localized: "\"Disconnect Meshtastic\" — disconnect from the connected BLE node.")
			)
		}
	}

	var body: some View {
		NavigationStack(path: $navigationPath) {
			// The welcome page is the stack's root rather than a pushed destination, so it
			// needs the name here; the rest get it below.
			welcomeView
				.padding(.top, 44)
				.trackScreen(SetupGuide.welcome.screenName)
				.navigationDestination(for: SetupGuide.self) { guide in
					Group {
						switch guide {
						case .welcome:
							welcomeView
						case .notifications:
							notificationView
						case .location:
							locationView
						case .bluetooth:
							bluetoothView
						case .localNetwork:
							localNetworkView
						case .siri:
							siriView
						}
					}
					.trackScreen(guide.screenName)
				}
		}
		.interactiveDismissDisabled()
		.toolbar(.hidden)
	}

	// MARK: Navigation
	func nextStep(
		after step: SetupGuide?,
		notificationStatus: UNAuthorizationStatus,
		criticalAlertSetting: UNNotificationSetting,
		locationStatus: CLAuthorizationStatus
	) -> SetupGuide? {
		switch step {
		case .none:
			return .welcome
		case .welcome:
			return .bluetooth
		case .bluetooth:
			return .localNetwork
		case .localNetwork:
			return .notifications
		case .notifications:
			if locationStatus.allowsLocationUse {
				return .siri
			}
			return .location
		case .location:
			return .siri
		case .siri:
			return nil
		}
	}

	func goToNextStep(after step: SetupGuide?) async {
		let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
		locationStatus = LocationsHandler.shared.manager.authorizationStatus

		if let next = nextStep(
			after: step,
			notificationStatus: notificationSettings.authorizationStatus,
			criticalAlertSetting: notificationSettings.criticalAlertSetting,
			locationStatus: locationStatus
		) {
			navigationPath.append(next)
		} else {
			dismiss()
		}
	}

}

// MARK: Formatting
extension DeviceOnboarding {
	/// Links the word "settings" in an intro sentence to the app's page in the Settings app.
	private func linkingSettings(_ text: AttributedString) -> AttributedString {
		var fullText = text
		if let range = fullText.range(of: String(localized: "settings"))
			?? fullText.range(of: "settings") {
			fullText[range].link = URL(string: UIApplication.openSettingsURLString)!
			fullText[range].foregroundColor = .blue
		}
		return fullText
	}

	func createNotificationsString() -> AttributedString {
		linkingSettings(AttributedString(localized: "Allow Meshtastic to send you notifications for messages, node events, and critical alerts. You can update notification permissions at any time from settings."))
	}

	func createLocationString() -> AttributedString {
		linkingSettings(AttributedString(localized: "Your phone's location goes only to your connected radio. Your radio shares nothing until you turn it on. Public channels get an approximate location and never your exact position. You can change location permissions at any time from settings."))
	}

	func createLocalNetworkString() -> AttributedString {
		linkingSettings(AttributedString(localized: "Meshtastic accesses your local network to connect to TCP-based accessories.  You can update the local network permissions at any time from settings."))
	}

	func createBluetoothString() -> AttributedString {
		linkingSettings(AttributedString(localized: "Meshtastic uses Bluetooth to connect to BLE-based accessories.  You can update the permissions at any time from settings."))
	}

	func createSiriString() -> AttributedString {
		linkingSettings(AttributedString(localized: "Meshtastic supports Siri, Shortcuts, and CarPlay so you can send and receive messages hands-free. You can update Siri permissions at any time from settings."))
	}
}

// MARK: Permission Checks
extension DeviceOnboarding {
	func requestNotificationsPermissions() async {
		let center = UNUserNotificationCenter.current()
		do {
			let success = try await center.requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert])
			if success {
				Logger.services.info("Notification permissions are enabled")
			} else {
				Logger.services.info("Notification permissions denied")
			}
		} catch {
			Logger.services.error("Notification permissions error: \(error.localizedDescription)")
		}
	}

	func requestLocationPermissions() async {
		let currentStatus = LocationsHandler.shared.manager.authorizationStatus
		let locationServicesEnabled = CLLocationManager.locationServicesEnabled()

		// On Mac Catalyst, if location services are disabled or already denied/restricted,
		// the system won't show a permission prompt. Open System Settings instead.
		#if targetEnvironment(macCatalyst)
		if !locationServicesEnabled || currentStatus == .denied || currentStatus == .restricted {
			Logger.services.info("Location services disabled or denied on Mac, opening System Settings")
			if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
				await UIApplication.shared.open(url)
			}
			locationStatus = currentStatus
			return
		}
		#endif

		if !locationServicesEnabled || currentStatus == .denied || currentStatus == .restricted {
			Logger.services.info("Location services not available, opening app settings")
			if let url = URL(string: UIApplication.openSettingsURLString) {
				await UIApplication.shared.open(url)
			}
			locationStatus = currentStatus
			return
		}

		locationStatus = await LocationsHandler.shared.requestLocationAlwaysPermissions()
		if locationStatus != .notDetermined {
			Logger.services.info("Location permissions are enabled")
		} else {
			Logger.services.info("Location permissions denied")
		}
	}

	func requestLocalNetworkPermissions() async {
		_ = await TCPTransport.requestLocalNetworkAuthorization()
	}

	func requestBluetoothPermissions() async {
		_ = await BluetoothAuthorizationHelper.requestBluetoothAuthorization()
	}

	func requestSiriPermissions() async {
		if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
			Logger.services.info("Skipping Siri permission request while running tests")
			return
		}

		#if targetEnvironment(macCatalyst)
		// Siri authorization prompt is not available on Mac Catalyst
		Logger.services.info("Siri permissions not available on Mac Catalyst")
		#else
		await withCheckedContinuation { continuation in
			INPreferences.requestSiriAuthorization { status in
				switch status {
				case .authorized:
					Logger.services.info("Siri permissions are enabled")
				case .denied:
					Logger.services.info("Siri permissions denied")
				default:
					Logger.services.info("Siri permissions status: \(status.rawValue)")
				}
				continuation.resume()
			}
		}
		#endif
	}
}

#Preview {
	DeviceOnboarding()
		.environmentObject(AccessoryManager.shared)
}
