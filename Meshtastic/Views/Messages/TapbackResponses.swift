import SwiftUI

struct TapbackResponses: View {
	let tapbacks: [MessageEntity]

	/// Each reaction chip is a fixed width instead of sizing to its own emoji/name — this makes
	/// the pill's total content width exactly computable (see `pillWidth`) without any runtime
	/// measurement. (A `GeometryReader`-based measurement of the grid's natural size, taken
	/// inside the `ScrollView`'s content, did not resolve reliably — it read back 0 every time —
	/// and a plain `.fixedSize()` + `.frame(maxWidth:)` chain on the `ScrollView` itself always
	/// resolved to the cap width regardless of content, since a `ScrollView`'s ideal size along
	/// its scroll axis isn't content-driven the way a stack's is. Fixed-width items sidestep
	/// both: the total is arithmetic, not measured.)
	private static let itemWidth: CGFloat = 40
	private static let itemSpacing: CGFloat = 12
	private static let gridPadding: CGFloat = 10

	/// Caps the pill at roughly the same width budget a message bubble gets: screen width minus
	/// the avatar circle (50pt + 10pt padding), the opposite-side spacer (50pt), and the row's
	/// own horizontal padding (16pt/side). A few reactions still hug tightly well under this; a
	/// long run (e.g. a popular broadcast) clips to it and scrolls horizontally instead of
	/// overflowing past the screen edge with the rounded border pushed off-screen.
	private static let maxWidth: CGFloat = UIScreen.main.bounds.width - 142

	/// One row for a handful of reactions, two once there are several — then scroll
	/// horizontally instead of overflowing the screen (matches the emoji picker styling).
	private var rowCount: Int { tapbacks.count > 6 ? 2 : 1 }

	private var rows: [GridItem] {
		Array(repeating: GridItem(.fixed(38), spacing: 4), count: rowCount)
	}

	/// Exact content width from the fixed item width, capped at `maxWidth`.
	private var pillWidth: CGFloat {
		let columnCount = Int((Double(tapbacks.count) / Double(rowCount)).rounded(.up))
		let contentWidth = CGFloat(columnCount) * Self.itemWidth
			+ CGFloat(max(0, columnCount - 1)) * Self.itemSpacing
			+ 2 * Self.gridPadding
		return min(contentWidth, Self.maxWidth)
	}

	@ViewBuilder
	var body: some View {
		if !tapbacks.isEmpty {
			VStack(alignment: .trailing) {
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHGrid(rows: rows, spacing: Self.itemSpacing) {
						ForEach(tapbacks) { (tapback: MessageEntity) in
							VStack(spacing: 1) {
								Text(tapback.messagePayload ?? "")
									.font(.system(size: 20))
									.lineLimit(1)
									.minimumScaleFactor(0.7)
								Text("\(tapback.fromUser?.shortName ?? "?")")
									.font(.caption2)
									.foregroundColor(.gray)
									.lineLimit(1)
									.minimumScaleFactor(0.7)
							}
							.frame(width: Self.itemWidth)
							.accessibilityElement(children: .combine)
							.accessibilityLabel(String(localized: "Reaction \(tapback.messagePayload ?? "") from \(tapback.fromUser?.shortName ?? "?")", comment: "VoiceOver: a single emoji reaction and who sent it. First value is the emoji, second is the sender"))
						}
					}
					.padding(Self.gridPadding)
				}
				.frame(width: pillWidth, alignment: .trailing)
				.overlay(
					RoundedRectangle(cornerRadius: 18)
						.stroke(Color.gray, lineWidth: 1)
				)
			}
		}
	}
}
