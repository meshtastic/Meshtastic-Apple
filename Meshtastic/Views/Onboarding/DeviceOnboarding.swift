import CoreBluetooth
import Intents
import OSLog
import SwiftUI
import Foundation
import MapKit

struct DeviceOnboarding: View {
	enum SetupGuide: Hashable {
		case notifications
		case location
		case bluetooth
		case localNetwork
		case siri
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
	var notificationView: some View {
		VStack {
			ScrollView(.vertical) {
				VStack {
					Text("App Notifications")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.horizontal)
				VStack(alignment: .leading, spacing: 16) {
					Text(createNotificationsString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					Text("Send Notifications")
						.font(.title2.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "message",
						title: String(localized: "Incoming Messages"),
						subtitle: String(localized: "Notifications for channel and direct messages."),
						isOn: $channelMessageNotifications
					)
					makeRow(
						icon: "flipphone",
						color: .green,
						title: String(localized: "New Nodes"),
						subtitle: String(localized: "Notifications for newly discovered nodes."),
						isOn: $newNodeNotifications
					)
					makeRow(
						icon: "battery.25percent",
						color: .orange,
						title: String(localized: "Low Battery"),
						subtitle: String(localized: "Notifications for low battery alerts for the connected device."),
						isOn: $lowBatteryNotifications
					)
					Text("Critical Alerts")
						.font(.title2.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "exclamationmark.triangle.fill",
						color: .red,
						subtitle: String(localized: "Select packets sent as critical will ignore the mute switch and Do Not Disturb settings in the OS notification center.")
					)
				}
				.padding()
			}
			Spacer()
			Button {
				Task {
					await requestNotificationsPermissions()
					await goToNextStep(after: .notifications)
				}
			} label: {
				Text("Continue")
					.frame(maxWidth: 400)
			}
			.capsuleButtonStyle()
			.padding(.bottom)
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
		VStack {
			ScrollView(.vertical) {
				VStack {
					Text("Phone Location")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.horizontal)
				VStack(alignment: .leading, spacing: 16) {
					Text(createLocationString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "location",
						title: String(localized: "Share Location"),
						subtitle: String(localized: "Use your phone GPS to send locations to your node to instead of using a hardware GPS on your node."),
						isOn: $provideLocation
					)
					.onChange(of: provideLocation) {
						UserDefaults.provideLocationInterval = 30
						UserDefaults.enableSmartPosition = true
					}
					makeRow(
						icon: "location.fill",
						title: String(localized: "Continuous Location Updates"),
						subtitle: String(localized: "Keep the mesh map updated and send your position to the mesh even while using other apps."),
						isOn: $locationsHandler.backgroundActivity
					)
					makeRow(
						icon: "lines.measurement.horizontal",
						color: .indigo,
						title: String(localized: "Distance Measurements"),
						subtitle: String(localized: "Display the distance between your phone and other Meshtastic nodes with positions.")
					)
					makeRow(
						icon: "line.3.horizontal.decrease.circle",
						color: .orange,
						title: String(localized: "Distance Filters"),
						subtitle: String(localized: "Filter the node list and mesh map based on proximity to your phone.")
					)
					makeRow(
						icon: "mappin",
						color: .green,
						title: String(localized: "Mesh Map Location"),
						subtitle: String(localized: "Enables the blue location dot for your phone in the mesh map.")
					)
				}
				.padding()
			}
			Spacer()
			Button {
				Task {
					await requestLocationPermissions()
					await goToNextStep(after: .location)
				}
			} label: {
				Text("Continue")
					.frame(maxWidth: 400)
			}
			.capsuleButtonStyle()
			.padding(.bottom)
		}
	}
	
	var localNetworkView: some View {
		VStack {
			ScrollView(.vertical) {
				VStack {
					Text("Local Network Access")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.horizontal)
				VStack(alignment: .leading, spacing: 16) {
					Text(createLocalNetworkString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "network",
						color: .green,
						title: "Network-based Nodes".localized,
						subtitle: "The Meshtastic App can connect to and manage network-enabled nodes.".localized
					)
					makeRow(
						icon: "person.and.background.dotted",
						color: .indigo,
						title: "Background Connections".localized,
						subtitle: "Background network connections are not supported and may disconnect when you leave the app.".localized
					)
					makeRow(
						icon: "arrow.trianglehead.2.clockwise",
						color: .orange,
						title: "Minimum Firmware Version".localized,
						subtitle: "For the best connection experience, minimum firmware version 2.7.4 is required.".localized
					)
				}
				.padding()
			}
			Spacer()
			Button {
				Task {
					await requestLocalNetworkPermissions()
					await goToNextStep(after: .localNetwork)
				}
			} label: {
				Text("Continue")
					.frame(maxWidth: 400)
			}
			.capsuleButtonStyle()
			.padding(.bottom)
		}
	}
	
	var bluetoothView: some View {
		VStack {
			ScrollView(.vertical) {
				VStack {
					Text("Bluetooth Connectivity")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.horizontal)
				.padding(.top, 44)
				VStack(alignment: .leading, spacing: 16) {
					Text(createBluetoothString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "custom.bluetooth",
						color: .teal,
						title: "Bluetooth Connected Nodes".localized,
						subtitle: "The most reliable messaging experience is with Bluetooth Low Energy connected nodes.".localized
					)
					makeRow(
						icon: "person.and.background.dotted",
						color: .indigo,
						title: "Background Connections".localized,
						subtitle: "Bluetooth Low Energy supports background connections. When possible, the application will remain connected to these accessories while the app is in the background.".localized
					)
				}
				.padding()
			}
			Spacer()
			Button {
				Task {
					await requestBluetoothPermissions()
					await goToNextStep(after: .bluetooth)
				}
			} label: {
				Text("Continue")
					.frame(maxWidth: 400)
			}
			.capsuleButtonStyle()
			.padding(.bottom)
		}
	}
	
	var siriView: some View {
		VStack {
			ScrollView(.vertical) {
				VStack {
					Text("Siri, Shortcuts & CarPlay")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.horizontal)
				VStack(alignment: .leading, spacing: 16) {
					Text(createSiriString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "car.fill",
						color: .red,
						title: String(localized: "CarPlay Messaging"),
						subtitle: String(localized: "Read and reply to Meshtastic channel and direct messages directly from your car's display using CarPlay.")
					)
					makeRow(
						icon: "message",
						title: String(localized: "Send a Group Message"),
						subtitle: String(localized: "\"Send a Meshtastic group message\" — send a message to a mesh channel.")
					)
					makeRow(
						icon: "bubble",
						color: .indigo,
						title: String(localized: "Send a Direct Message"),
						subtitle: String(localized: "\"Send a Meshtastic direct message\" — send a private message to a node.")
					)
					makeRow(
						icon: "power",
						color: .orange,
						title: String(localized: "Shut Down / Restart Node"),
						subtitle: String(localized: "\"Shut down my Meshtastic node\" or \"Restart my Meshtastic node\".")
					)
					makeRow(
						icon: "antenna.radiowaves.left.and.right.slash",
						color: .green,
						title: String(localized: "Disconnect Node"),
						subtitle: String(localized: "\"Disconnect Meshtastic\" — disconnect from the connected BLE node.")
					)
				}
				.padding()
			}
			Spacer()
			Button {
				Task {
					await requestSiriPermissions()
					await goToNextStep(after: .siri)
				}
			} label: {
				Text("Continue")
					.frame(maxWidth: 400)
			}
			.capsuleButtonStyle()
			.padding(.bottom)
		}
	}
	
	var body: some View {
		NavigationStack(path: $navigationPath) {
			bluetoothView
				.navigationDestination(for: SetupGuide.self) { guide in
					switch guide {
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
		}
		.interactiveDismissDisabled()
		.toolbar(.hidden)
	}

	@ViewBuilder
	func makeCompactRow(icon: String, title: String, subtitle: String) -> some View {
		HStack(alignment: .center, spacing: 12) {
			Group {
				if icon.starts(with: "custom.") {
					Image(icon)
						.resizable()
						.symbolRenderingMode(.multicolor)
				} else {
					Image(systemName: icon)
						.resizable()
						.symbolRenderingMode(.multicolor)
				}
			}
			.aspectRatio(contentMode: .fit)
			.frame(width: 28, height: 28)
			.padding(.leading, 4)
			VStack(alignment: .leading, spacing: 1) {
				Text(title)
					.font(.footnote.weight(.semibold))
					.foregroundColor(.primary)
				Text(subtitle)
					.font(.caption)
					.foregroundColor(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.accessibilityElement(children: .combine)
	}

	@ViewBuilder
	func makeRow(
		icon: String,
		color: Color = .accentColor,
		title: String = "",
		subtitle: String,
		isOn: Binding<Bool>? = nil
	) -> some View {
		HStack(alignment: .center) {
			ZStack {
				RoundedRectangle(cornerRadius: 11)
					.fill(color.opacity(0.1))
					.frame(width: 40, height: 40)
				if icon.starts(with: "custom.") {
					Image(icon)
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(width: 22, height: 22)
						.foregroundStyle(color)
				} else {
					Image(systemName: icon)
						.font(.system(size: 20))
						.foregroundStyle(color)
				}
			}
			.frame(width: 72, height: 60)
			VStack(alignment: .leading) {
				Text(title)
					.font(.footnote.weight(.semibold))
					.foregroundColor(.primary)
					.fixedSize(horizontal: false, vertical: true)
				Text(subtitle)
					.font(.footnote)
					.foregroundColor(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}.multilineTextAlignment(.leading)
			if let binding = isOn {
				Spacer()
				Toggle("", isOn: binding)
					.labelsHidden()
					.fixedSize()
					.tint(.accentColor)
			}
		}.accessibilityElement(children: .combine)
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
			return .bluetooth
		case .bluetooth:
			return .localNetwork
		case .localNetwork:
			return .notifications
		case .notifications:
			if locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways {
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
	
	// MARK: Formatting
	func createNotificationsString() -> AttributedString {
		var fullText = AttributedString("Allow Meshtastic to send you notifications for messages, node events, and critical alerts. You can update notification permissions at any time from settings.")
		if let range = fullText.range(of: "settings") {
			fullText[range].link = URL(string: UIApplication.openSettingsURLString)!
			fullText[range].foregroundColor = .blue
		}
		return fullText
	}

	func createLocationString() -> AttributedString {
		var fullText = AttributedString(localized: "Meshtastic uses your phone's location to enable a number of features. You can update your location permissions at any time from settings.")
		if let range = fullText.range(of: String(localized: "settings")) {
			fullText[range].link = URL(string: UIApplication.openSettingsURLString)!
			fullText[range].foregroundColor = .blue
		}
		return fullText
	}
	
	func createLocalNetworkString() -> AttributedString {
		var fullText = AttributedString("Meshtastic accesses your local network to connect to TCP-based accessories.  You can update the local network permissions at any time from settings.")
		if let range = fullText.range(of: "settings") {
			fullText[range].link = URL(string: UIApplication.openSettingsURLString)!
			fullText[range].foregroundColor = .blue
		}
		return fullText
	}
	
	func createBluetoothString() -> AttributedString {
		var fullText = AttributedString("Meshtastic uses Bluetooth to connect to BLE-based accessories.  You can update the permissions at any time from settings.")
		if let range = fullText.range(of: "settings") {
			fullText[range].link = URL(string: UIApplication.openSettingsURLString)!
			fullText[range].foregroundColor = .blue
		}
		return fullText
	}
	
	func createSiriString() -> AttributedString {
		var fullText = AttributedString("Meshtastic supports Siri, Shortcuts, and CarPlay so you can send and receive messages hands-free. You can update Siri permissions at any time from settings.")
		if let range = fullText.range(of: "settings") {
			fullText[range].link = URL(string: UIApplication.openSettingsURLString)!
			fullText[range].foregroundColor = .blue
		}
		return fullText
	}
	
	// MARK: Permission Checks
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
