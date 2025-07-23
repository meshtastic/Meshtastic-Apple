import SwiftUI

struct AppIconPicker: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.managedObjectContext) var context
	@Environment(\.dismiss) var dismiss
	@State private var didError = false
	@State private var errorDetails: String?
	var iconNames: [String?: String] = [nil: "Default", "AppIcon_Dev": "Develop"]
	var meshGroupIconNames: [String?: String] = ["AppIcon_MN_MSP": "MSP Mesh"]

	// MARK: View
	var body: some View {
		List {
			Section(header: Text("General")) {
				ForEach(Array(iconNames.sorted(by: { $0.0 ?? "1" < $1.0 ?? "1"}).enumerated()), id: \.offset) { _, icon in
					AppIconButton(iconDescription: .constant(icon.value), iconName: .constant(icon.key))
				}
			}
			Section(header: Text("Local Meshes")) {
				ForEach(Array(meshGroupIconNames.sorted(by: { $0.0 ?? "1" < $1.0 ?? "1"}).enumerated()), id: \.offset) { _, icon in
					AppIconButton(iconDescription: .constant(icon.value), iconName: .constant(icon.key))
				}
			}
		}
		.navigationTitle("App Icon")
	}
}

#Preview{
	AppIconPicker()
}
