import SwiftUI

struct AlertButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Text("Alert")
			Image(systemName: "bell.fill")
				.symbolRenderingMode(.hierarchical)
				.imageScale(.large)
				.foregroundColor(.accentColor)
		}
	}
}

struct AlertButtonPreview: PreviewProvider {
	static var previews: some View {
		AlertButton {}
	}
}
