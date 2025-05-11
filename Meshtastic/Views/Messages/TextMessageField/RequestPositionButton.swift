import SwiftUI

struct RequestPositionButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: "mappin.and.ellipse")
				.accessibilityLabel(NSLocalizedString("request_position", comment: "VoiceOver label for request position button"))
				.symbolRenderingMode(.hierarchical)
				.imageScale(.large)
				.foregroundColor(.accentColor)
		}
		.padding(.trailing)
	}
}

struct RequestPositionButtonPreview: PreviewProvider {
	static var previews: some View {
		RequestPositionButton {}
	}
}
