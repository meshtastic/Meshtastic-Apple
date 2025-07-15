import CoreBluetooth
import OSLog
import SwiftUI
import Foundation
import MapKit

struct DeviceOnboarding: View {
	enum SetupGuide: Hashable {
		case notifications
		case location
	}

	@EnvironmentObject var bleManager: BLEManager
	@State var navigationPath: [SetupGuide] = []
	@State var locationStatus = LocationsHandler.shared.manager.authorizationStatus

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
			ScrollView(.vertical, showsIndicators: false) {
				VStack {
					// Title
					title
						.padding(.top)
					// Onboarding
					VStack(alignment: .leading, spacing: 16) {
						makeRow(
							icon: "antenna.radiowaves.left.and.right",
							title: "Stay Connected Anywhere",
							subtitle: "Communicate off-the-grid with your friends and community without cell service."
						)

						makeRow(
							icon: "point.3.connected.trianglepath.dotted",
							title: "Create Your Own Networks",
							subtitle: "Easily set up private mesh networks for secure and reliable communication in remote areas."
						)

						makeRow(
							icon: "location",
							title: "Track and Share Locations",
							subtitle: "Share your location in real-time and keep your group coordinated with integrated GPS features."
						)
					}
					.padding()
				}
				.interactiveDismissDisabled()
			}
			Spacer()
			if bleManager.isSwitchedOn {
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
	}

	var notificationView: some View {
		VStack {
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
					title: "Incoming Messages",
					subtitle: "Meshtastic notifications for channel messages and direct messages"
				)
				makeRow(
					icon: "flipphone",
					title: "New Nodes",
					subtitle: "Allow Meshtastic to send notifications for messages, newly discovered nodes and low battery alerts for the connected device."
				)
				makeRow(
					icon: "battery.25percent",
					title: "Low Battery",
					subtitle: "Allow Meshtastic to send notifications for messages, newly discovered nodes and low battery alerts for the connected device."
				)
				Text("Critical Alerts")
					.font(.title2.bold())
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
				makeRow(
					icon: "exclamationmark.triangle.fill",
					subtitle: "Select packets sent as critical will ignore the mute switch and Do Not Disturb settings in the OS notification center."
				)
			}
			.padding()
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
			VStack {
				Text("Phone Location")
					.font(.largeTitle.bold())
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
			VStack(alignment: .leading, spacing: 16) {
				Text("Meshtastic uses your phone's location to enable a number of features. You can update your location permissions at any time from Settings > App Settings > Open Settings.")
					.font(.body.bold())
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
				makeRow(
					icon: "location",
					title: "Share Location",
					subtitle: "Use your phone GPS to send locations to your node to instead of using a hardware GPS on your node."
				)
				makeRow(
					icon: "lines.measurement.horizontal",
					title: "Distance Measurements",
					subtitle: "Used to display the distance between your phone and other Meshtastic nodes where positions are available."
				)
				makeRow(
					icon: "line.3.horizontal.decrease.circle",
					title: "Distance Filters",
					subtitle: "Filter the node list and mesh map based on proximity to your phone."
				)
				makeRow(
					icon: "mappin",
					title: "Mesh Map Location",
					subtitle: "Enables the blue location dot for your phone in the mesh map."
				)
			}
			.padding()
			Spacer()
			Button {
				Task {
					await requestLocationPermissions()
				}
				UserDefaults.firstLaunch = false
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

	var body: some View {
		NavigationStack(path: $navigationPath) {
			welcomeView
				.navigationDestination(for: SetupGuide.self) { guide in
					switch guide {
					case .notifications:
						notificationView
					case .location:
						locationView
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
			Image(systemName: icon)
				.resizable()
				.symbolRenderingMode(.multicolor)
				.font(.subheadline)
				.aspectRatio(contentMode: .fit)
				.padding()
				.frame(width: 72, height: 72)

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
			let status = LocationsHandler.shared.manager.authorizationStatus
			if status != .notDetermined && status != .restricted && status != .denied {
				dismiss()
			}
		}
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
			Logger.services.info("Notification permissions are enabled")
		} else {
			Logger.services.info("Notification permissions denied")
		}
		dismiss()
	}
}
