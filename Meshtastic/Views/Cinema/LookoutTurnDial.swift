//
//  LookoutTurnDial.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
#if os(visionOS)
import SwiftUI

/// A compass dial on the cinema panel for which way the fire lookout's cab faces, in eighth turns.
/// Tap one of its eight marks or drag round it; the turn is made when you let go, so the terrain
/// isn't rebuilt for every mark passed on the way.
struct LookoutTurnDial: View {
	@Binding var turns: Int
	/// Where a drag is pointing, before it's let go.
	@State private var dragTurns: Int?

	private static let size: CGFloat = 140

	var body: some View {
		let shown = dragTurns ?? turns
		let heading = SpatialLookout.heading(turns: shown)
		VStack(spacing: 6) {
			Text("Turn Lookout", comment: "Cinema: title over the dial that turns the fire lookout, so the screen looks out over another part of the view")
				.font(.subheadline)
			dial(shown: shown, heading: heading)
			Text(verbatim: SpatialLookout.facing(heading: heading))
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text("Turn Lookout", comment: "Cinema: title over the dial that turns the fire lookout, so the screen looks out over another part of the view"))
		.accessibilityValue(Text(verbatim: SpatialLookout.facing(heading: heading)))
		.accessibilityAdjustableAction { direction in
			switch direction {
			case .increment: turns = (turns + 1) % 8
			case .decrement: turns = (turns + 7) % 8
			@unknown default: break
			}
		}
	}

	private func dial(shown: Int, heading: Double) -> some View {
		let radius = Self.size / 2
		return ZStack {
			Circle()
				.fill(.quaternary)
			ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
				Text(verbatim: letter)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.offset(Self.offset(bearing: Double(index) * 90, radius: radius * 0.62))
			}
			ForEach(0..<8, id: \.self) { mark in
				Circle()
					.fill(mark == shown ? Color.accentColor : Color.secondary.opacity(0.6))
					.frame(width: mark == shown ? 14 : 9, height: mark == shown ? 14 : 9)
					.offset(Self.offset(bearing: SpatialLookout.heading(turns: mark), radius: radius * 0.86))
			}
			Image(systemName: "location.north.fill")
				.font(.system(size: 26))
				.foregroundStyle(Color.accentColor)
				.rotationEffect(.degrees(heading))
		}
		.frame(width: Self.size, height: Self.size)
		.contentShape(Circle())
		.hoverEffect(.highlight)
		.gesture(
			DragGesture(minimumDistance: 0)
				.onChanged { value in
					dragTurns = Self.turns(at: value.location, radius: radius)
				}
				.onEnded { value in
					turns = Self.turns(at: value.location, radius: radius)
					dragTurns = nil
				}
		)
	}

	/// The offset from the dial's center of a point `radius` out at `bearing`, north up.
	private static func offset(bearing: Double, radius: CGFloat) -> CGSize {
		let angle = bearing * .pi / 180
		return CGSize(width: radius * sin(angle), height: -radius * cos(angle))
	}

	/// The turn nearest the bearing of `location` from the dial's center.
	private static func turns(at location: CGPoint, radius: CGFloat) -> Int {
		let bearing = atan2(location.x - radius, radius - location.y) * 180 / .pi
		return SpatialLookout.turns(nearest: (bearing + 360).truncatingRemainder(dividingBy: 360))
	}
}
#endif
