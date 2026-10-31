//
//  DeviceRemoteControl.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import SwiftUI

/// The radio's buttons: four direction wedges around an OK disc, with Back below (design#142 §6.1).
/// Holding a direction repeats it; holding OK sends a long press.
struct DeviceRemoteControl: View {

	let send: (DisplayInputEvent) -> Void

	private let diameter: CGFloat = 220
	private let okRadius: CGFloat = 40
	/// The gap between the OK disc and the wedges, so a slightly-off tap does nothing rather than the wrong thing.
	private let deadBand: CGFloat = 8

	var body: some View {
		VStack(spacing: 16) {
			ZStack {
				DirectionWedge(event: .up, label: "Up", systemImage: "chevron.up", angle: .degrees(-90), innerRadius: okRadius + deadBand, send: send)
				DirectionWedge(event: .right, label: "Right", systemImage: "chevron.right", angle: .degrees(0), innerRadius: okRadius + deadBand, send: send)
				DirectionWedge(event: .down, label: "Down", systemImage: "chevron.down", angle: .degrees(90), innerRadius: okRadius + deadBand, send: send)
				DirectionWedge(event: .left, label: "Left", systemImage: "chevron.left", angle: .degrees(180), innerRadius: okRadius + deadBand, send: send)
				OKButton(radius: okRadius, send: send)
			}
			.frame(width: diameter, height: diameter)

			Button {
				send(.back)
			} label: {
				Label("Back", systemImage: "arrow.uturn.backward")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.roundedRectangle)
			.controlSize(.large)
		}
		.frame(maxWidth: .infinity)
	}
}

/// A quarter of the ring centered on `angle`. Hit testing follows the wedge shape.
private struct DirectionWedge: View {

	let event: DisplayInputEvent
	let label: LocalizedStringKey
	let systemImage: String
	let angle: Angle
	let innerRadius: CGFloat
	let send: (DisplayInputEvent) -> Void

	/// Resets on its own when the system cancels the touch, which onEnded doesn't see.
	@GestureState private var isPressed = false
	@State private var repeatTask: Task<Void, Never>?

	var body: some View {
		GeometryReader { proxy in
			let outerRadius = min(proxy.size.width, proxy.size.height) / 2
			let iconRadius = (innerRadius + outerRadius) / 2
			let shape = RingSector(center: angle, innerRadius: innerRadius)
			ZStack {
				shape
					.fill(isPressed ? Color.accentColor.opacity(0.35) : Color(.secondarySystemFill))
				Image(systemName: systemImage)
					.font(.title2.weight(.semibold))
					.foregroundStyle(.primary)
					.position(
						x: proxy.size.width / 2 + iconRadius * cos(angle.radians),
						y: proxy.size.height / 2 + iconRadius * sin(angle.radians)
					)
			}
			.contentShape(shape)
			.gesture(
				DragGesture(minimumDistance: 0)
					.updating($isPressed) { _, pressed, _ in
						pressed = true
					}
			)
		}
		.onChange(of: isPressed) { _, pressed in
			if pressed {
				startRepeating()
			} else {
				stopRepeating()
			}
		}
		.onDisappear { stopRepeating() }
		.accessibilityElement()
		.accessibilityLabel(label)
		.accessibilityAddTraits(.isButton)
		.accessibilityAction { send(event) }
	}

	private func stopRepeating() {
		repeatTask?.cancel()
		repeatTask = nil
	}

	private func startRepeating() {
		send(event)
		repeatTask?.cancel()
		repeatTask = Task { @MainActor in
			try? await Task.sleep(for: DisplayInputMapping.repeatDelay)
			while !Task.isCancelled {
				send(event)
				try? await Task.sleep(for: DisplayInputMapping.repeatInterval)
			}
		}
	}
}

private struct OKButton: View {

	let radius: CGFloat
	let send: (DisplayInputEvent) -> Void

	var body: some View {
		Circle()
			.fill(Color.accentColor)
			.overlay {
				Text("OK")
					.font(.headline)
					.foregroundStyle(.white)
			}
			.frame(width: radius * 2, height: radius * 2)
			.contentShape(Circle())
			.gesture(
				LongPressGesture(minimumDuration: DisplayInputMapping.longPressDuration)
					.onEnded { _ in send(.selectLong) }
					.exclusively(before: TapGesture().onEnded { send(.select) })
			)
			.accessibilityElement()
			.accessibilityLabel("OK")
			.accessibilityAddTraits(.isButton)
			.accessibilityAction { send(.select) }
			.accessibilityAction(named: "Long Press") { send(.selectLong) }
	}
}

/// A 90° slice of a ring, from `innerRadius` out to the edge of the frame.
private struct RingSector: Shape {

	let center: Angle
	let innerRadius: CGFloat

	func path(in rect: CGRect) -> Path {
		let mid = CGPoint(x: rect.midX, y: rect.midY)
		let outerRadius = min(rect.width, rect.height) / 2
		// A small gap between wedges keeps them reading as separate buttons.
		let gap = Angle.degrees(2)
		let start = center - .degrees(45) + gap
		let end = center + .degrees(45) - gap
		var path = Path()
		path.addArc(center: mid, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
		path.addArc(center: mid, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
		path.closeSubpath()
		return path
	}
}
