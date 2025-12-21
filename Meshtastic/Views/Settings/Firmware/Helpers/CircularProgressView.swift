//
//  CircularProgressView.swift
//  Meshtastic
//
//  Created by jake on 12/18/25.
//

import SwiftUI

struct CircularProgressView: View {
	let progress: Double
	var isIndeterminate: Bool = false
	
	var lineWidth: CGFloat = 20
	var size: CGFloat = 150
	var strokeColor: Color = .blue
	var backgroundColor: Color = .gray.opacity(0.2)
	var percentageFontSize: CGFloat = 48.0
	var subtitleText: String = "Loading..."
	var showSubtitle: Bool = true
	
	@State private var rotation: Double = 0
	
	private var isComplete: Bool {
		progress >= 1.0 && !isIndeterminate
	}
	
	var body: some View {
		ZStack {
			// 1. Background circle
			Circle()
				.stroke(backgroundColor, lineWidth: lineWidth)
			
			// 2. Progress circle
			Circle()
				.trim(from: 0, to: isIndeterminate ? 0.25 : progress)
				.stroke(
					isComplete ? .green : strokeColor,
					style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
				)
				// Logic: If indeterminate, spin. If not, fixed at -90 (12 o'clock)
				.rotationEffect(.degrees(isIndeterminate ? rotation : -90))
				// Only animate the progress filling up, not the mode switch
				.animation(isIndeterminate ? nil : .spring(response: 0.6), value: progress)
				
				// This tells SwiftUI: "If isIndeterminate changes, this is a NEW view."
				// This forces the old spinning view to be destroyed (killing the animation)
				// and a new static view to be created.
				.id(isIndeterminate)
			
			// 3. Content
			if isComplete {
				completedView
			} else {
				inProgressView
			}
		}
		.frame(width: size, height: size)
		.onAppear {
			updateAnimationStatus()
		}
		.onChange(of: isIndeterminate) { _, _ in
			updateAnimationStatus()
		}
	}
	
	private func updateAnimationStatus() {
		if isIndeterminate {
			// Reset rotation to 0 without animation to start clean
			rotation = 0
			// Start the infinite spin
			withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
				rotation = 360
			}
		} else {
			// Determine mode: The .id() modifier handles the visual stop,
			// but we reset the state here for cleanliness.
			// We use a transaction to disable animations for this state reset.
			var transaction = Transaction()
			transaction.disablesAnimations = true
			withTransaction(transaction) {
				rotation = 0
			}
		}
	}
	
	// Extracted views remain the same...
	private var completedView: some View {
		ZStack {
			Circle()
				.fill(Color.green.opacity(0.15))
				.frame(width: size * 0.6, height: size * 0.6)
			
			Image(systemName: "checkmark.circle.fill")
				.font(.system(size: percentageFontSize * 1.5, weight: .bold))
				.foregroundColor(.green)
		}
		.transition(.scale.combined(with: .opacity))
	}
	
	private var inProgressView: some View {
		VStack(spacing: 8) {
			if !isIndeterminate {
				Text("\(Int(progress * 100))%")
					.font(.system(size: percentageFontSize, weight: .bold))
					.foregroundColor(.primary)
					.contentTransition(.numericText())
					.animation(.default, value: progress)
			} else {
				Image(systemName: "clock")
					.font(.system(size: percentageFontSize * 0.8))
					.foregroundColor(strokeColor)
			}
			
			if showSubtitle {
				// Modified to prefer the passed-in text unless it's empty,
				// falling back to "Please wait" only if needed.
				Text(isIndeterminate && subtitleText == "Loading..." ? "Please wait" : subtitleText)
					.font(.callout)
					.foregroundColor(.secondary)
			}
		}
		.transition(.opacity)
	}
}
