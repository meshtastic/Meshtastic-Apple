import SwiftUI

struct InvalidVersion: View {
	@State
	var minimumVersion: String
	@State
	var version: String

	@Environment(\.dismiss)
	private var dismiss

	var body: some View {
		VStack {
			Text("update.firmware")
				.font(.largeTitle)
				.foregroundColor(.orange)

			Divider()

			VStack {
				Text("The Meshtastic Apple apps support firmware version \(minimumVersion) and above.")
					.font(.body)
					.padding(.bottom)

				Link(
					"Firmware update docs",
					// swiftlint:disable:next force_unwrapping
					destination: URL(string: "https://meshtastic.org/docs/getting-started/flashing-firmware/")!
				)
				.font(.body)
				.padding()

				Link(
					"Additional help",
					// swiftlint:disable:next force_unwrapping
					destination: URL(string: "https://meshtastic.org/docs/faq")!
				)
				.font(.body)
				.padding()
			}
			.padding()

			Divider()
				.padding(.top)

			VStack {
				Text("🦕 End of life Version 🦖 ☄️")
					.font(.title3)
					.foregroundColor(.orange)
					.padding(.bottom)

				Text("Version \(minimumVersion) includes breaking changes to devices and the client apps. Only nodes version \(minimumVersion) and above are supported.")
					.font(.callout)
					.padding([.leading, .trailing, .bottom])

				Link(
					"Version 1.2 End of life (EOL) Info",
					destination: URL(string: "https://meshtastic.org/docs/1.2-End-of-life/")!
				)
				.font(.callout)
			}.padding()
		}
	}
}
