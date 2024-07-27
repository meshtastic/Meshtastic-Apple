import CoreBluetooth
import OSLog
import SwiftUI

struct OnboardingView: View {
	enum SetupGuide: Hashable {
		case bluetooth
		case notifications
		case location
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
			.padding()
			.buttonStyle(.borderedProminent)
		}
	}

	var bluetoothView: some View {
		VStack {
			Text("Setup Bluetooth")
			Spacer()
			Button {
				// TODO: permission check
			} label: {
				Text("Enable bluetooth")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.buttonStyle(.borderedProminent)

			Button {
				Task {

				}
			} label: {
				Text("Set up later in settings")
					.frame(maxWidth: .infinity)
			}
		}
	}

	var notificationView: some View {
		VStack {
			Text("Enable notifications?")
			Spacer()
			Button {
				Task {
					await requestNotificationsPermissions()
					await goToNextStep(after: .notifications)
				}
			} label: {
				Text("Enable notifications")
					.frame(maxWidth: .infinity)
			}
			.padding()
			.buttonStyle(.borderedProminent)

			Button {
				Task {
					await goToNextStep(after: .notifications)
				}
			} label: {
				Text("Set up later in settings")
					.frame(maxWidth: .infinity)
			}
		}
	}

	var locationView: some View {
		VStack {
			Text("Enable location services")
			Spacer()
			Button {
				Task {
					await requestLocationPermissions()
				}
			} label: {
				Text("Enable location services")
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
					case .bluetooth:
						bluetoothView
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
		title: String,
		subtitle: String
	) -> some View {
		HStack(alignment: .center) {
			Image(systemName: icon)
				.resizable()
				.symbolRenderingMode(.multicolor)
				.font(.subheadline)
				.aspectRatio(contentMode: .fill)
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
			if CBCentralManager.authorization == .notDetermined {
				navigationPath.append(.bluetooth)
			} else {
				fallthrough
			}
		case .bluetooth:
			let center = UNUserNotificationCenter.current()
			let status = await center.notificationSettings().authorizationStatus
			if status == .notDetermined {
				navigationPath.append(.notifications)
				return
			} else {
				fallthrough
			}
		case .notifications:
			let status = LocationHelper.shared
				.locationManager
				.authorizationStatus
			if status == .notDetermined {
				navigationPath.append(.location)
			} else {
				fallthrough
			}
		case .location:
			dismiss()
		}
	}

	// MARK: Permission Checks

	func requestBluetoothPermissions() async {
		_ = CBCentralManager(delegate: nil, queue: nil)
	}

	func requestNotificationsPermissions() async {
		let center = UNUserNotificationCenter.current()
		let status = await center.notificationSettings().authorizationStatus
		guard status == .notDetermined else { return }
		do {
			let success = try await center.requestAuthorization(options: [.alert, .badge, .sound])
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
		LocationHelper.shared.locationManager.requestAlwaysAuthorization()
	}
}
