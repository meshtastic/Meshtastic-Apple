import SwiftUI

struct AlertButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: "bell.and.waves.left.and.right")
				.foregroundColor(.primary)
		}
	}
}

struct AlertButtonPreview: PreviewProvider {
	static var previews: some View {
		AlertButton {}
	}
}
