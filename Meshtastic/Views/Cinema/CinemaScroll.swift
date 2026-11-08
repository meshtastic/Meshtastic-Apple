//
//  CinemaScroll.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//
#if os(visionOS)
import SwiftUI

/// A board drawn as a parchment scroll hanging between two wooden rollers, for the castle tower.
/// Tapping either roller rolls the scroll up to the top one, out of the view, or lets it down
/// again. The scroll keeps its full size while rolled up, so its panel is fitted the same either
/// way, and the space it leaves is clear, so the view behind it shows.
struct CinemaScroll<Board: View>: View {
	/// How thick a roller is, and how far its knobbed ends reach past each side of the parchment,
	/// as fractions of the parchment's width. scripts/cinema/castle_tower.py sizes the frame's
	/// anchors with the same fractions.
	static var rollerFraction: CGFloat { 0.045 }
	static var overhangFraction: CGFloat { 0.055 }

	let board: CinemaBoard
	@ViewBuilder let content: () -> Board
	@AppStorage private var rolled: Bool

	init(board: CinemaBoard, @ViewBuilder content: @escaping () -> Board) {
		self.board = board
		self.content = content
		_rolled = AppStorage(wrappedValue: false, "cinemaScrollRolled.\(board.rawValue)")
	}

	var body: some View {
		let unrolled: CGFloat = rolled ? 0 : 1
		ScrollLayout(unrolled: unrolled) {
			content()
				.overlay {
					// Parchment darkened toward its edges. Only at the edges, so the board's ink keeps
					// its contrast.
					Rectangle()
						.strokeBorder(Self.edge, lineWidth: 18)
						.blur(radius: 14)
				}
				.mask {
					GeometryReader { proxy in
						Rectangle()
							.frame(height: proxy.size.height * unrolled)
							.frame(maxHeight: .infinity, alignment: .top)
					}
				}
				.accessibilityHidden(rolled)
			roller(rolledUp: 0)
			roller(rolledUp: 1 - unrolled)
		}
		.animation(.easeInOut(duration: 0.6), value: rolled)
	}

	private static var edge: Color { Color(red: 0.42, green: 0.3, blue: 0.16).opacity(0.55) }

	/// A turned wooden roller with a knob on each end. `rolledUp` is how much of the parchment is
	/// wound round it, 0 to 1, which shows as a band of parchment thickening over the wood.
	private func roller(rolledUp: CGFloat) -> some View {
		Button {
			rolled.toggle()
		} label: {
			GeometryReader { proxy in
				let height = proxy.size.height
				let knob = height * 1.25
				ZStack {
					Rectangle()
						.fill(Self.wood)
						.padding(.horizontal, knob / 2)
						.padding(.vertical, height * 0.12)
					if rolledUp > 0 {
						Rectangle()
							.fill(Self.parchment)
							.padding(.horizontal, proxy.size.width * Self.overhangFraction / (1 + 2 * Self.overhangFraction) + knob * 0.2)
							.padding(.vertical, height * 0.12 * (1 - rolledUp))
					}
					HStack {
						Circle().fill(Self.knob).frame(width: knob, height: knob)
						Spacer(minLength: 0)
						Circle().fill(Self.knob).frame(width: knob, height: knob)
					}
				}
				.frame(width: proxy.size.width, height: height)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.hoverEffect(.highlight)
		.accessibilityLabel(rolled
			? String(localized: "Unroll the scroll", comment: "Cinema: VoiceOver label for a roller on a scroll in the castle tower; lets the rolled-up scroll down")
			: String(localized: "Roll up the scroll", comment: "Cinema: VoiceOver label for a roller on a scroll in the castle tower; rolls the scroll up out of the view"))
	}

	/// Shaded top to bottom like a cylinder lit from above.
	private static var wood: LinearGradient {
		LinearGradient(
			colors: [Color(red: 0.42, green: 0.27, blue: 0.14), Color(red: 0.6, green: 0.41, blue: 0.22), Color(red: 0.3, green: 0.18, blue: 0.09), Color(red: 0.17, green: 0.1, blue: 0.05)],
			startPoint: .top,
			endPoint: .bottom
		)
	}

	private static var parchment: LinearGradient {
		LinearGradient(
			colors: [Color(red: 0.86, green: 0.78, blue: 0.62), Color(red: 0.72, green: 0.63, blue: 0.48), Color(red: 0.5, green: 0.42, blue: 0.3)],
			startPoint: .top,
			endPoint: .bottom
		)
	}

	private static var knob: RadialGradient {
		RadialGradient(
			colors: [Color(red: 0.62, green: 0.43, blue: 0.24), Color(red: 0.24, green: 0.14, blue: 0.07)],
			center: UnitPoint(x: 0.4, y: 0.35),
			startRadius: 0,
			endRadius: 60
		)
	}
}

/// Lays out a scroll: the parchment (the first view) between a roller across the top (the second)
/// and one across the bottom (the third), the rollers reaching past its sides. The whole is sized
/// from the parchment, whatever is shown of it; the bottom roller rides up with `unrolled`.
private struct ScrollLayout: Layout {
	var unrolled: CGFloat

	var animatableData: CGFloat {
		get { unrolled }
		set { unrolled = newValue }
	}

	private func parts(_ parchment: CGSize) -> (roller: CGFloat, overhang: CGFloat) {
		(parchment.width * CinemaScroll<EmptyView>.rollerFraction, parchment.width * CinemaScroll<EmptyView>.overhangFraction)
	}

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		guard let parchment = subviews.first?.sizeThatFits(.unspecified) else { return .zero }
		let (roller, overhang) = parts(parchment)
		return CGSize(width: parchment.width + 2 * overhang, height: parchment.height + 2 * roller)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		guard subviews.count == 3 else { return }
		let parchment = subviews[0].sizeThatFits(.unspecified)
		let (roller, overhang) = parts(parchment)
		subviews[0].place(at: CGPoint(x: bounds.minX + overhang, y: bounds.minY + roller), proposal: ProposedViewSize(parchment))
		let rollerSize = ProposedViewSize(width: bounds.width, height: roller)
		subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: rollerSize)
		subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.minY + roller + parchment.height * unrolled), proposal: rollerSize)
	}
}
#endif
