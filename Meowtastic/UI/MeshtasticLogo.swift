import SwiftUI

struct MeshtasticLogo: View {
	@Environment(\.colorScheme)
	var colorScheme

	@ViewBuilder
	var body: some View {
		Image(colorScheme == .dark ? "logo-white" : "logo-black")
			.resizable()
			.scaledToFit()
			.frame(height: 32)
	}
}
