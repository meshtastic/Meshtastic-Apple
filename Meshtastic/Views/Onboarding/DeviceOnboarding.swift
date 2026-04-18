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
		case backgroundActivity
		case localNetwork
		case bluetooth
		case siri
	}
	
	@EnvironmentObject var accessoryManager: AccessoryManager
	@ObservedObject private var locationsHandler: LocationsHandler = .shared
	@State var navigationPath: [SetupGuide] = []
	@State var locationStatus = LocationsHandler.shared.manager.authorizationStatus
	@AppStorage("provideLocation") private var provideLocation: Bool = false
	@AppStorage("provideLocationInterval") private var provideLocationInterval: Int = 30
	@Environment(\.dismiss) var dismiss
	/// The Title View
	var title: some View {
		VStack {
			Text("Welcome to Meshtastic")
				.font(.title.bold())
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
		}
	}
	
	var welcomeView: some View {
		VStack(spacing: 0) {
			ScrollView(.vertical) {
				VStack {
					// Title
					title
						.padding(.top)
					VStack(alignment: .leading, spacing: 16) {
						makeRow(
							icon: "antenna.radiowaves.left.and.right",
							title: String(localized: "Stay Connected Anywhere"),
							subtitle: String(localized: "Communicate off-the-grid with your friends and community without cell service.")
						)
						makeRow(
							icon: "point.3.connected.trianglepath.dotted",
							title: String(localized: "Create Your Own Networks"),
							subtitle: String(localized: "Easily set up private mesh networks for secure and reliable communication in remote areas.")
						)
						makeRow(
							icon: "location",
							title: String(localized: "Track and Share Locations"),
							subtitle: String(localized: "Share your location in real-time and keep your group coordinated with integrated GPS features.")
						)
						makeRow(
							icon: "person.2.shield",
							title: String(localized: "User Privacy"),
							subtitle: String(localized: "Meshtastic does not collect any personal information. We do anonymously collect usage and crash data to improve the app.")
						)
						makeRow(
							icon: "bell.badge",
							title: String(localized: "Message Notifications"),
							subtitle: String(localized: "Receive notifications for incoming messages and critical alerts even when the app is in the background.")
						)
						makeRow(
							icon: "custom.bluetooth",
							title: String(localized: "Bluetooth Connectivity"),
							subtitle: String(localized: "Connect to your Meshtastic node via Bluetooth Low Energy for the best messaging experience.")
						)
						makeRow(
							icon: "network",
							title: String(localized: "Local Network Access"),
							subtitle: String(localized: "Connect to nodes on your local Wi-Fi network.")
						)
						makeRow(
							icon: "car.fill",
							title: String(localized: "Siri & CarPlay"),
							subtitle: String(localized: "Send and receive Meshtastic messages hands-free using Siri and CarPlay.")
						)
					}
					.padding(.horizontal)
					.padding(.bottom)
				}
			}
			.interactiveDismissDisabled()
			Button {
				Task {
					await goToNextStep(after: nil)
				}
			} label: {
				Text("Get started")
					.frame(maxWidth: .infinity)
			}
			.capsuleButtonStyle()
		}
	}
	
	var notificationView: some View {
		VStack {
			ScrollView(.vertical) {
				VStack {
					Text("App Notifications")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
				Spacer()
				VStack(alignment: .leading, spacing: 16) {
					Text("Send Notifications")
						.font(.title2.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "message",
						title: String(localized: "Incoming Messages"),
						subtitle: String(localized: "Notifications for channel and direct messages.")
					)
					makeRow(
						icon: "flipphone",
						title: String(localized: "New Nodes"),
						subtitle: String(localized: "Notifications for newly discovered nodes.")
					)
					makeRow(
						icon: "battery.25percent",
						title: String(localized: "Low Battery"),
						subtitle: String(localized: "Notifications for low battery alerts for the connected device.")
					)
					Text("Critical Alerts")
						.font(.title2.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "exclamationmark.triangle.fill",
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
				Text("Configure notification permissions")
					.frame(maxWidth: .infinity)
			}
			.capsuleButtonStyle()
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
				VStack(alignment: .leading, spacing: 16) {
					Text(createLocationString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "location",
						title: String(localized: "Share Location"),
						subtitle: String(localized: "Use your phone GPS to send locations to your node to instead of using a hardware GPS on your node.")
					)
					Toggle(isOn: $provideLocation ) {
						Label {
							Text("Enable Location Sharing")
						} icon: {
							Image(systemName: "location.circle")
						}
					}
					.fixedSize()
					.scaleEffect(0.85)
					.padding(.leading, 52)
					.tint(.accentColor)
					.onChange(of: provideLocation) {
						UserDefaults.provideLocationInterval = 30
						UserDefaults.enableSmartPosition = true
					}
					makeRow(
						icon: "lines.measurement.horizontal",
						title: String(localized: "Distance Measurements"),
						subtitle: String(localized: "Display the distance between your phone and other Meshtastic nodes with positions.")
					)
					makeRow(
						icon: "line.3.horizontal.decrease.circle",
						title: String(localized: "Distance Filters"),
						subtitle: String(localized: "Filter the node list and mesh map based on proximity to your phone.")
					)
					makeRow(
						icon: "mappin",
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
				}
			} label: {
				Text("Configure Location Permissions")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.capsuleButtonStyle()
		}
	}
	
	var backgroundActivityView: some View {
		VStack {
			ScrollView(.vertical) {
				VStack {
					Text("Background Activity")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
				VStack(alignment: .leading, spacing: 16) {
					Text(createBackgroundActivityString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "location.fill",
						title: String(localized: "Continuous Location Updates"),
						subtitle: String(localized: "Keep the mesh map updated and send your position to the mesh even while using other apps.")
					)
					makeRow(
						icon: "antenna.radiowaves.left.and.right",
						title: String(localized: "Background Mesh Tracking"),
						subtitle: String(localized: "Receive position updates from other nodes and maintain an accurate picture of the mesh while in the background.")
					)
					makeRow(
						icon: "battery.100.bolt",
						title: String(localized: "Battery Usage"),
						subtitle: String(localized: "Enabling background activity may increase battery usage. You can toggle this at any time in the app settings.")
					)
					Toggle(isOn: $locationsHandler.backgroundActivity) {
						Label {
							Text("Enable Background Activity")
						} icon: {
							Image(systemName: "location.circle")
						}
					}
					.fixedSize()
					.scaleEffect(0.85)
					.padding(.leading, 52)
					.tint(.accentColor)
				}
				.padding()
			}
			Spacer()
			Button {
				Task {
					await goToNextStep(after: .backgroundActivity)
				}
			} label: {
				Text("Continue")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.capsuleButtonStyle()
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
				VStack(alignment: .leading, spacing: 16) {
					Text(createLocalNetworkString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "network",
						title: "Network-based Nodes".localized,
						subtitle: "The Meshtastic App can connect to and manage network-enabled nodes.".localized
					)
					makeRow(
						icon: "person.and.background.dotted",
						title: "Background Connections".localized,
						subtitle: "Background network connections are not supported and may disconnect when you leave the app.".localized
					)
					makeRow(
						icon: "arrow.trianglehead.2.clockwise",
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
				Text("Configure Local Network Access")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.capsuleButtonStyle()
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
				VStack(alignment: .leading, spacing: 16) {
					Text(createBluetoothString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "custom.bluetooth",
						title: "Bluetooth Connected Nodes".localized,
						subtitle: "The most reliable messaging experience is with Bluetooth Low Energy connected nodes.".localized
					)
					makeRow(
						icon: "person.and.background.dotted",
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
				Text("Configure Bluetooth Connectivity")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.capsuleButtonStyle()
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
				VStack(alignment: .leading, spacing: 16) {
					Text(createSiriString())
						.font(.body.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
					makeRow(
						icon: "car.fill",
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
						title: String(localized: "Send a Direct Message"),
						subtitle: String(localized: "\"Send a Meshtastic direct message\" — send a private message to a node.")
					)
					makeRow(
						icon: "power",
						title: String(localized: "Shut Down / Restart Node"),
						subtitle: String(localized: "\"Shut down my Meshtastic node\" or \"Restart my Meshtastic node\".")
					)
					makeRow(
						icon: "antenna.radiowaves.left.and.right.slash",
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
				Text("Configure Siri & Shortcuts")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.capsuleButtonStyle()
		}
	}
	
	var body: some View {
		NavigationStack(path: $navigationPath) {
			welcomeView
				.navigationDestination(for: SetupGuide.self) { guide in
					switch guide {
					case .notifications:
						notificationView
					case .location:
						locationView
					case .backgroundActivity:
						backgroundActivityView
					case .bluetooth:
						bluetoothView
					case .localNetwork:
						localNetworkView
					case .siri:
						siriView
					}
				}
		}
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
		title: String = "",
		subtitle: String
	) -> some View {
		HStack(alignment: .center) {
			if icon.starts(with: "custom.") {
				Image(icon)
					.resizable()
					.symbolRenderingMode(.multicolor)
					.font(.subheadline)
					.aspectRatio(contentMode: .fit)
					.padding(.horizontal)
					.padding(.vertical, 8)
					.frame(width: 72, height: 60)
			} else {
				Image(systemName: icon)
					.resizable()
					.symbolRenderingMode(.multicolor)
					.font(.subheadline)
					.aspectRatio(contentMode: .fit)
					.padding(.horizontal)
					.padding(.vertical, 8)
					.frame(width: 72, height: 60)
			}
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
		}.accessibilityElement(children: .combine)
	}
	// MARK: Navigation
	func goToNextStep(after step: SetupGuide?) async {
		switch step {
		case .none:
			let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
			let criticalAlert = await UNUserNotificationCenter.current().notificationSettings().criticalAlertSetting
			if  status == .notDetermined && criticalAlert == .notSupported {
				navigationPath.append(.notifications)
			} else {
				fallthrough
			}
		case .notifications:
			locationStatus = LocationsHandler.shared.manager.authorizationStatus
			if locationStatus == .notDetermined ||  locationStatus == .restricted || locationStatus == .denied {
				navigationPath.append(.location)
			} else {
				fallthrough
			}
		case .location:
			locationStatus = LocationsHandler.shared.manager.authorizationStatus
			if locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways {
				navigationPath.append(.backgroundActivity)
			}
		case .backgroundActivity:
			navigationPath.append(.localNetwork)
		case .localNetwork:
			navigationPath.append(.bluetooth)
			
		case .bluetooth:
			navigationPath.append(.siri)
		case .siri:
			dismiss()
		}
	}
	
	// MARK: Formatting
	func createBackgroundActivityString() -> AttributedString {
		var fullText = AttributedString("Meshtastic can track your location in the background to keep the mesh map updated and send your position to the mesh even when the app is not in the foreground. You can update this setting at any time from settings.")
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
		locationStatus = await LocationsHandler.shared.requestLocationAlwaysPermissions()
		if locationStatus != .notDetermined {
			Logger.services.info("Location permissions are enabled")
		} else {
			Logger.services.info("Location permissions denied")
		}
		await goToNextStep(after: .location)
	}
	
	func requestLocalNetworkPermissions() async {
		_ = await TCPTransport.requestLocalNetworkAuthorization()
	}
	
	func requestBluetoothPermissions() async {
		_ = await BluetoothAuthorizationHelper.requestBluetoothAuthorization()
	}
	
	func requestSiriPermissions() async {
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
	}

}

#Preview {
	DeviceOnboarding()
		.environmentObject(AccessoryManager.shared)
}
