import SwiftUI

struct TextMessageSize: View {
	let maxbytes: Int
	let totalBytes: Int

	var body: some View {
		ProgressView("\("Bytes".localized): \(totalBytes) / \(maxbytes)", value: Double(totalBytes), total: Double(maxbytes))
			.accessibilityLabel(NSLocalizedString("message_size", comment: "VoiceOver label for message size"))
			.accessibilityValue(String(format: NSLocalizedString("bytes_used", comment: "VoiceOver value for bytes used"), totalBytes, maxbytes))
			.frame(width: 130)
			.padding(5)
			.font(.subheadline)
			.accentColor(.accentColor)
	}
}

struct TextMessageSizePreview: PreviewProvider {
	static var previews: some View {
		TextMessageSize(maxbytes: 200, totalBytes: 100)
	}
}
