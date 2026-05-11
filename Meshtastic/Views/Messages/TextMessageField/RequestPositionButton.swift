import SwiftUI

struct RequestPositionButton: View {
	let action: () -> Void
	var compact: Bool = false

	var body: some View {
		Button(action: action) {
			Image(systemName: "mappin.and.ellipse")
				.accessibilityLabel("Position Exchange Requested".localized)
				.symbolRenderingMode(.hierarchical)
				.imageScale(compact ? .medium : .large)
				.foregroundColor(compact ? .primary : .accentColor)
		}
		.frame(minWidth: compact ? 36 : nil, minHeight: compact ? 36 : nil)
		.padding(.trailing, compact ? 0 : nil)
	}
}

struct RequestPositionButtonPreview: PreviewProvider {
	static var previews: some View {
		RequestPositionButton {}
	}
}
