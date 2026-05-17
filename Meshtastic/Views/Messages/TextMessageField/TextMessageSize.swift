import SwiftUI

struct TextMessageSize: View {
	let maxbytes: Int
	let totalBytes: Int
	var compact: Bool = false

	var body: some View {
		ProgressView("\("Bytes".localized): \(totalBytes)", value: Double(totalBytes), total: Double(maxbytes))
			.accessibilityLabel(NSLocalizedString("Message Size", comment: "VoiceOver label for message size"))
			.accessibilityValue(String(format: NSLocalizedString("Bytes Used", comment: "VoiceOver value for bytes used"), totalBytes, maxbytes))
			.frame(width: compact ? nil : 130)
			.fixedSize(horizontal: compact, vertical: false)
			.padding(compact ? 0 : 5)
			.font(compact ? .caption2 : .subheadline)
			.lineLimit(1)
			.accentColor(.accentColor)
	}
}

struct TextMessageSizePreview: PreviewProvider {
	static var previews: some View {
		TextMessageSize(maxbytes: 200, totalBytes: 100)
	}
}
