import CoreBluetooth
import OSLog
import SwiftUI
import Foundation
import MapKit

struct DeviceOnboarding: View {
	enum SetupGuide: Hashable {
		case notifications
		case location
		case localNetwork
		case bluetooth
	}
	
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var navigationPath: [SetupGuide] = []
	@State var locationStatus = LocationsHandler.shared.manager.authorizationStatus
	@AppStorage("provideLocation") private var provideLocation: Bool = false
	@AppStorage("provideLocationInterval") private var provideLocationInterval: Int = 30
	@Environment(\.dismiss) var dismiss
	/// The Title View
	var title: some View {
		VStack {
			Text("Welcome to")
				.font(.title2.bold())
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
			Text("Meshtastic")
				.font(.largeTitle.bold())
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
		}
	}
	
	var welcomeView: some View {
		VStack {
			ScrollView(.vertical) {
				VStack {
					// Title
					title
						.padding(.top)
					// Onboarding
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
					}
					.padding()
				}
				.interactiveDismissDisabled()
			}
			Spacer()
			Button {
				Task {
					await goToNextStep(after: nil)
				}
			} label: {
				Text("Get started")
					.frame(maxWidth: .infinity)
			}
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.buttonStyle(.borderedProminent)
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
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.buttonStyle(.borderedProminent)
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
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.buttonStyle(.borderedProminent)
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
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.buttonStyle(.borderedProminent)
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
						subtitle: "Bluetooth Low Energy supports background connections.  When possible, the applicaiton will remain connected to these accessories while the app is in the background".localized
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
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.buttonStyle(.borderedProminent)
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
					case .bluetooth:
						bluetoothView
					case .localNetwork:
						localNetworkView
					}
				}
		}
		.toolbar(.hidden)
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
					.font(.subheadline.weight(.semibold))
					.foregroundColor(.primary)
					.fixedSize(horizontal: false, vertical: true)
				Text(subtitle)
					.font(.subheadline)
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
			if locationStatus != .notDetermined && locationStatus != .restricted {
				navigationPath.append(.localNetwork)
			}
		case .localNetwork:
			navigationPath.append(.bluetooth)
			
		case .bluetooth:
			dismiss()
		}
	}
	
	// MARK: Formatting
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

}
