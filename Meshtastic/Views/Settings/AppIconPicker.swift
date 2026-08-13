import SwiftUI

struct AppIconOption: Identifiable, Equatable {
	let id: String
	let iconName: String?
	let description: String
}

struct AppIconPicker: View {
	@Binding var isPresenting: Bool

	static let iconOptions = [
		AppIconOption(id: "default", iconName: nil, description: "Default"),
		AppIconOption(id: "mpowered", iconName: "AppIcon_MPowered", description: "Meshtastic Powered"),
		AppIconOption(id: "chirpy", iconName: "AppIcon_Chirpy", description: "Chirpy"),
		AppIconOption(id: "ham", iconName: "AppIcon_Ham", description: "Ham")
	]

	var body: some View {
		List {
			Section(header: Text("Icons")) {
				ForEach(Self.iconOptions) { icon in
					AppIconButton(
						iconDescription: .constant(icon.description),
						iconName: .constant(icon.iconName),
						isPresenting: $isPresenting
					)
				}
			}
		}
	}
}

#Preview {
	AppIconPicker(isPresenting: .constant(true))
}
