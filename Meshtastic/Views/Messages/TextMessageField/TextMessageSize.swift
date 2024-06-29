import SwiftUI

struct TextMessageSize: View {
	let maxbytes: Int
	let totalBytes: Int

	var body: some View {
		ProgressView("\(NSLocalizedString("bytes", comment: "No comment provided")): \(totalBytes) / \(maxbytes)", value: Double(totalBytes), total: Double(maxbytes))
			.frame(width: 130)
			.padding(5)
			.font(.subheadline)
			.accentColor(.accentColor)
	}
}

struct TextMessageSizePreview: PreviewProvider {
	static var previews: some View {
		TextMessageSize(maxbytes: 228, totalBytes: 100)
	}
}
