import SwiftUI

struct TapbackResponses: View {
	let tapbacks: [MessageEntity]

	/// One row for a handful of reactions, two once there are several — then scroll
	/// horizontally instead of overflowing the screen (matches the emoji picker styling).
	private var rows: [GridItem] {
		Array(repeating: GridItem(.fixed(38), spacing: 4), count: tapbacks.count > 6 ? 2 : 1)
	}

	@ViewBuilder
	var body: some View {
		if !tapbacks.isEmpty {
			VStack(alignment: .trailing) {
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHGrid(rows: rows, spacing: 12) {
						ForEach(tapbacks) { (tapback: MessageEntity) in
							VStack(spacing: 1) {
								Text(tapback.messagePayload ?? "")
									.font(.system(size: 20))
									.lineLimit(1)
									.fixedSize()
								Text("\(tapback.fromUser?.shortName ?? "?")")
									.font(.caption2)
									.foregroundColor(.gray)
									.fixedSize()
							}
						}
					}
					.padding(10)
				}
				// Hug the reactions so the border wraps the content instead of leaving
				// empty space; the up-to-two-rows layout keeps realistic counts on-screen.
				.fixedSize(horizontal: true, vertical: false)
				.overlay(
					RoundedRectangle(cornerRadius: 18)
						.stroke(Color.gray, lineWidth: 1)
				)
			}
		}
	}
}
