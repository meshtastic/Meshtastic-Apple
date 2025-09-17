import SwiftUI

struct AppIconPicker: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.managedObjectContext) var context
	@Binding var isPresenting: Bool
	@State private var didError = false
	@State private var errorDetails: String?
	var iconNames: [String?: String] = [nil: "Default", "AppIcon_MPowered": "Meshtastic Powered", "AppIcon_Chirpy": "Chirpy", "AppIcon_Ham": "Ham"]

	// MARK: View
	var body: some View {
		List {
			Section(header: Text("Icons")) {
				ForEach(Array(iconNames.enumerated()), id: \.offset) { _, icon in
					AppIconButton(iconDescription: .constant(icon.value), iconName: .constant(icon.key), isPresenting: $isPresenting)
				}
			}
		}
	}
}

#Preview{
	AppIconPicker(isPresenting: .constant(true))
}
