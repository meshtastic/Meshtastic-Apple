import SwiftUI

struct RequestPositionButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: "mappin.and.ellipse")
				.foregroundColor(.primary)
		}
	}
}

struct RequestPositionButtonPreview: PreviewProvider {
	static var previews: some View {
		RequestPositionButton {}
	}
}
