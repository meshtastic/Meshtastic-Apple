import SwiftUI

struct AppIconPicker: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.managedObjectContext) var context
	@Binding var isPresenting: Bool
	@State private var didError = false
	@State private var errorDetails: String?
	var iconNames: [String?: String] = [nil: "Default", "AppIcon_Dev": "Develop", "AppIcon_Testflight": "Testflight"]
	var chirpyIconNames: [String?: String] = ["AppIcon_Chirpy": "Chirpy", "AppIcon_Chirpy_Testflight": "Chirpy - Testflight"]

	// MARK: View
	var body: some View {
		List {
			Section(header: Text("General")) {
				ForEach(Array(iconNames.sorted(by: { $0.0 ?? "1" < $1.0 ?? "1"}).enumerated()), id: \.offset) { _, icon in
					AppIconButton(iconDescription: .constant(icon.value), iconName: .constant(icon.key), isPresenting: $isPresenting)

				}
			}
			Section(header: Text("Chirpy")) {
				ForEach(Array(chirpyIconNames.sorted(by: { $0.0 ?? "1" < $1.0 ?? "1"}).enumerated()), id: \.offset) { _, icon in
					AppIconButton(iconDescription: .constant(icon.value), iconName: .constant(icon.key), isPresenting: $isPresenting)
				}
			}
		}
	}
}

#Preview{
	AppIconPicker(isPresenting: .constant(true))
}
