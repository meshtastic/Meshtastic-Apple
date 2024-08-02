import StoreKit
import SwiftUI

struct About: View {
	private let locale = Locale.current

	@EnvironmentObject
	private var bleManager: BLEManager

	@ViewBuilder
	var body: some View {
		List {
			Section(header: Text("Meshtastic")) {
				Text(
	"""
	An open source, off-grid, decentralized, mesh network built to run on affordable, low-power devices
	"""
				)
				.font(.body)

				Link(
					"Project Website",
					// swiftlint:disable:next force_unwrapping
					destination: URL(string: "https://meshtastic.org")!
				)
				.font(.body)

				Text(
					"Meshtastic® is a registered trademark of Meshtastic LLC"
				)
				.font(.footnote)
			}

			Section(header: Text("This Application")) {
				Button("Rate it") {
					if let scene = UIApplication.shared.connectedScenes.first(where: {
						$0.activationState == .foregroundActive
					}) as? UIWindowScene {
						SKStoreReviewController.requestReview(in: scene)
					}
				}
				.font(.body)

				Link(
					"Source",
					// swiftlint:disable:next force_unwrapping
					destination: URL(string: "https://github.com/c4t-dr34m/meowtastic_ios")!
				)
				.font(.body)

				Text("Version: \(Bundle.main.appVersionLong); build \(Bundle.main.appBuild)")
			}
		}
		.navigationTitle("About")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarItems(
			trailing: ConnectedDevice()
		)
	}
}
