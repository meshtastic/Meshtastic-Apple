//
//  TraceRoute.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/22/24.
//
import SwiftUI

struct Rotation: LayoutValueKey {
	static let defaultValue: Binding<Angle>? = nil
}

struct TraceRouteComponent<V: View>: View {
	var animation: Animation?
	@ViewBuilder let content: () -> V
	@State private var rotation: Angle = .zero

	var body: some View {
		content()
			.rotationEffect(rotation)
			.layoutValue(key: Rotation.self, value: $rotation.animation(animation))
	}
}

struct TraceRoute: Layout {
	var animatableData: AnimatablePair<CGFloat, CGFloat> {
		get {
			AnimatablePair(rotation.radians, radius)
		}
		set {
			rotation = Angle.radians(newValue.first)
			radius = newValue.second
		}
	}

	var radius: CGFloat
	var rotation: Angle

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let maxSize = subviews.map { $0.sizeThatFits(proposal) }.reduce(CGSize.zero) {
			return CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
		}
		return CGSize(width: (maxSize.width / 2 + radius) * 2,
					  height: (maxSize.height / 2 + radius) * 2)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let angleStep = (Angle.degrees(360).radians / Double(subviews.count))

		for (index, subview) in subviews.enumerated() {
			let angle = angleStep * CGFloat(index) + rotation.radians

			var point = CGPoint(x: 0, y: -radius).applying(CGAffineTransform(rotationAngle: angle))
			point.x += bounds.midX
			point.y += bounds.midY

			subview.place(at: point, anchor: .center, proposal: .unspecified)

		//	DispatchQueue.main.async {
		//		if index % 2 == 0 {
		//			subview[Rotation.self]?.wrappedValue = .zero
		//		} else {
		//			subview[Rotation.self]?.wrappedValue = .radians(angle)
		//		}
		//	}
		}
	}
}
