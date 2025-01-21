import CoreBluetooth
import OSLog
import SwiftUI
import Foundation
import MapKit

struct OnboardingView: View {
	enum SetupGuide: Hashable {
		case notifications
		case location
		case mqtt
	}

	@State
	var navigationPath: [SetupGuide] = []

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
			Text("Enable location services")
			Spacer()
			Button {
				Task {
					await goToNextStep(after: .location)
				}
			} label: {
				Text("Enable location services")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.buttonStyle(.borderedProminent)

			Button {
				Task {
					await goToNextStep(after: .mqtt)
				}
			} label: {
				Text("Set up later")
					.frame(maxWidth: .infinity)
			}
		}
	}

	var mqttView: some View {
		VStack {
			Text("MQTT Settings")
			Spacer()
			Button {
				Task {

				}
			} label: {
				Text("Enable MQTT")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.buttonStyle(.borderedProminent)

			Button {
				dismiss()
			} label: {
				Text("Set up later")
					.frame(maxWidth: .infinity)
			}
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
					case .mqtt:
						mqttView
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
			if  status == .notDetermined {
				navigationPath.append(.notifications)
			} else {
				fallthrough
			}
		case .notifications:
			let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
			if  status == .notDetermined {
				await requestNotificationsPermissions()
			} else {
				fallthrough
			}
		case .location:
			let status = LocationHelper.shared
				.locationManager
				.authorizationStatus
			if status == .notDetermined {
				navigationPath.append(.location)
			} else {
				fallthrough
			}
		case .mqtt:
			dismiss()
		}
	}

	// MARK: Permission Checks

	func requestNotificationsPermissions() async -> UNAuthorizationStatus {
		let center = UNUserNotificationCenter.current()
		do {
			let success = try await center.requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert])
			if success {
				Logger.services.info("Notification permissions are enabled")
			} else {
				Logger.services.info("Notification permissions denied")
			}
			return await center.notificationSettings().authorizationStatus
		} catch {
			Logger.services.error("Notification permissions error: \(error.localizedDescription)")
			return .notDetermined
		}
	}
}
