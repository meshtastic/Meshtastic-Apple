import SwiftUI

struct AppIconPicker: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.managedObjectContext) var context
	@Binding var isPresenting: Bool
	@State private var didError = false
	@State private var errorDetails: String?
	var iconNames: [String?: String] = [nil: "Default", "AppIcon_Dev": "Develop", "AppIcon_Chirpy": "Chirpy"]

	// MARK: View
	var body: some View {
		List {
			Section(header: Text("Icons")) {
				ForEach(Array(iconNames.sorted(by: { $0.0 ?? "1" < $1.0 ?? "1"}).enumerated()), id: \.offset) { _, icon in
					if icon.value != "AppIcon_Dev" {
						AppIconButton(iconDescription: .constant(icon.value), iconName: .constant(icon.key), isPresenting: $isPresenting)
					}

#if DEBGUG
					if Bundle.main.isTestFlight && icon.key == "AppIcon_Testflight" {
						AppIconButton(iconDescription: .constant(icon.value), iconName: .constant(icon.key), isPresenting: $isPresenting)
					}
#endif
				}
			}
		}
	}
}

#Preview{
	AppIconPicker(isPresenting: .constant(true))
}
