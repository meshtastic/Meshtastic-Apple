import SwiftUI

struct AlertButton: View {
	let action: () -> Void
	var compact: Bool = false

	var body: some View {
		Button(action: action) {
			if !compact {
				Text("Alert")
			}
			Image(systemName: "bell.fill")
				.symbolRenderingMode(.hierarchical)
				.imageScale(compact ? .medium : .large)
				.foregroundColor(compact ? .primary : .accentColor)
		}
		.frame(minWidth: compact ? 36 : nil, minHeight: compact ? 36 : nil)
		.accessibilityLabel(String(localized: "Alert", comment: "VoiceOver: sends an alert bell to the conversation"))
	}
}

struct AlertButtonPreview: PreviewProvider {
	static var previews: some View {
		AlertButton {}
	}
}
