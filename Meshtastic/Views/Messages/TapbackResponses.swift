import SwiftUI

struct TapbackResponses: View {
	let tapbacks: [MessageEntity]

	/// Each reaction chip is a fixed width instead of sizing to its own emoji/name — this makes
	/// the pill's total content width exactly computable (see `contentWidth`) without any runtime
	/// measurement. (A `GeometryReader`-based measurement of the grid's natural size, taken
	/// inside the `ScrollView`'s content, did not resolve reliably — it read back 0 every time —
	/// and a plain `.fixedSize()` + `.frame(maxWidth:)` chain on the `ScrollView` itself always
	/// resolved to the cap width regardless of content, since a `ScrollView`'s ideal size along
	/// its scroll axis isn't content-driven the way a stack's is. Fixed-width items sidestep
	/// both: the total is arithmetic, not measured.)
	private static let itemWidth: CGFloat = 40
	private static let itemSpacing: CGFloat = 12
	private static let gridPadding: CGFloat = 10

	/// One row for a handful of reactions, two once there are several — then scroll
	/// horizontally instead of overflowing the column (matches the emoji picker styling).
	private var rowCount: Int { tapbacks.count > 6 ? 2 : 1 }

	private var rows: [GridItem] {
		Array(repeating: GridItem(.fixed(38), spacing: 4), count: rowCount)
	}

	/// Exact content width from the fixed item width. `ReactionPillFrame` caps it at the
	/// width the message column offers, so Split View and a fold update the pill.
	private var contentWidth: CGFloat {
		let columnCount = Int((Double(tapbacks.count) / Double(rowCount)).rounded(.up))
		return CGFloat(columnCount) * Self.itemWidth
			+ CGFloat(max(0, columnCount - 1)) * Self.itemSpacing
			+ 2 * Self.gridPadding
	}

	/// Exact content height, arithmetic like `contentWidth`: the grid rows are `.fixed(38)` with 4pt
	/// spacing plus the grid padding. Fixing the `ScrollView`'s height matters beyond cosmetics —
	/// a `ScrollView`'s ideal height isn't content-driven, so left flexible it competes with the
	/// message bubble's `Text` for the row's vertical space, and the loser is the bubble: a long
	/// wrapping message above a reaction pill tail-truncates with "…" (seen in the field on ~6-line
	/// messages). Sized exactly, the pill stops bidding for height it doesn't need.
	private var pillHeight: CGFloat {
		CGFloat(rowCount) * 38
			+ CGFloat(max(0, rowCount - 1)) * 4
			+ 2 * Self.gridPadding
	}

	@ViewBuilder
	var body: some View {
		if !tapbacks.isEmpty {
			VStack(alignment: .trailing) {
				ReactionPillFrame(contentWidth: contentWidth, height: pillHeight) {
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
				}
			}
			.overlay(
				RoundedRectangle(cornerRadius: 18)
					.stroke(Color.gray, lineWidth: 1)
			)
		}
	}
}

/// Width is the chip arithmetic, capped at the width the message column proposes.
/// A stored `UIScreen` width is the wrong screen in Split View and never updates when the phone folds.
private struct ReactionPillFrame: Layout {
	var contentWidth: CGFloat
	var height: CGFloat

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let width: CGFloat
		if let offered = proposal.width, offered > 0 {
			width = min(contentWidth, offered)
		} else {
			width = contentWidth
		}
		return CGSize(width: width, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		subviews.first?.place(
			at: bounds.origin,
			anchor: .topLeading,
			proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
		)
	}
}
