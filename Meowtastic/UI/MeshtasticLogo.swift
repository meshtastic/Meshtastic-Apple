import SwiftUI

struct MeshtasticLogo: View {
	@Environment(\.colorScheme)
	var colorScheme

	@ViewBuilder
	var body: some View {
		VStack {
			Image(colorScheme == .dark ? "logo-white" : "logo-black")
				.resizable()
				// .renderingMode(.template)
				.scaledToFit()
				.frame(height: 32)
		}
	}
}
