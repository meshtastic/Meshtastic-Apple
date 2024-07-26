import SwiftUI

// Location
// Bluetooth
// Notifications

struct OnboardingView: View {

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
    var body: some View {
		ZStack {
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
				Spacer()
				VStack {
					Spacer()
					Button {
						// TODO: move to next screen
					} label: {
						Text("Get started")
							.frame(maxWidth: .infinity, idealHeight: 44)
					}
					.padding()
					.buttonStyle(.borderedProminent)
				}
			}
		}
    }
}
