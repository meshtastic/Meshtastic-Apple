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
	var isError: Bool = false
	
	var lineWidth: CGFloat = 20
	var size: CGFloat = 150
	var strokeColor: Color = .blue
	var backgroundColor: Color = .gray.opacity(0.2)
	var errorColor: Color = .red
	var percentageFontSize: CGFloat = 48.0
	
	// Changed to Optional, removed showSubtitle
	var subtitleText: String?
	
	@State private var rotation: Double = 0
	
	private var isComplete: Bool {
		// Complete only if 100%, not indeterminate, and NOT an error
		progress >= 1.0 && !isIndeterminate && !isError
	}
	
	var body: some View {
		ZStack {
			// 1. Background circle
			Circle()
				.stroke(backgroundColor, lineWidth: lineWidth)
			
			// 2. Progress circle
			Circle()
				// If Error or Complete, show full circle. Else show progress/spin segment.
				.trim(from: 0, to: (isIndeterminate && !isError) ? 0.25 : ((isError || isComplete) ? 1.0 : progress))
				.stroke(
					// Color Logic: Error > Complete > Standard
					isError ? errorColor : (isComplete ? .green : strokeColor),
					style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
				)
				// Logic: If indeterminate and NOT error, spin. Else fixed at -90
				.rotationEffect(.degrees((isIndeterminate && !isError) ? rotation : -90))
			
				// MARK: - Animation Fix
				// Disable animation for Error, Indeterminate, or Reset
				.animation(
					(isIndeterminate || isError || progress == 0) ? nil : .spring(response: 0.6),
					value: progress
				)
				.id(isIndeterminate)
			
			// 3. Content Logic
			if isError {
				errorView
			} else if isComplete {
				completedView
			} else {
				inProgressView
			}
		}
		.frame(width: size, height: size)
		.onAppear {
			updateAnimationStatus()
		}
		// Monitor both Indeterminate and Error to stop/start animations
		.onChange(of: isIndeterminate) { _, _ in updateAnimationStatus() }
		.onChange(of: isError) { _, _ in updateAnimationStatus() }
	}
	
	private func updateAnimationStatus() {
		// Only spin if Indeterminate AND we are not in an Error state
		if isIndeterminate && !isError {
			rotation = 0
			withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
				rotation = 360
			}
		} else {
			var transaction = Transaction()
			transaction.disablesAnimations = true
			withTransaction(transaction) {
				rotation = 0
			}
		}
	}
	
	// MARK: - Subviews
	
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
	
	private var errorView: some View {
		VStack(spacing: 8) {
			ZStack {
				Circle()
					.fill(errorColor.opacity(0.15))
					.frame(width: size * 0.5, height: size * 0.5)
				
				Image(systemName: "exclamationmark.triangle.fill")
					.font(.system(size: percentageFontSize, weight: .bold))
					.foregroundColor(errorColor)
			}
			
			// Unwrapped optional check
			if let subtitleText {
				Text(subtitleText)
					.font(.caption)
					.fontWeight(.medium)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
					.lineLimit(2)
					.minimumScaleFactor(0.8)
					.padding(.horizontal, 10)
			}
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
					.animation(progress == 0 ? nil : .default, value: progress)
			} else {
				Image(systemName: "clock")
					.font(.system(size: percentageFontSize * 0.8))
					.foregroundColor(strokeColor)
			}
			
			// Unwrapped optional check
			if let text = subtitleText {
				Text(isIndeterminate && text == "Loading..." ? "Please wait" : text)
					.font(.callout)
					.foregroundColor(.secondary)
			}
		}
		.transition(.opacity)
	}
}

// MARK: - Preview
#Preview {
	VStack(spacing: 40) {
		// Standard Progress with subtitle
		CircularProgressView(progress: 0.45, subtitleText: "Syncing...")
			.frame(height: 150)
		
		// Error State with subtitle
		CircularProgressView(
			progress: 0.45,
			isError: true,
			subtitleText: "Connection Failed"
		)
		.frame(height: 150)
		
		// No Subtitle
		CircularProgressView(progress: 0.75, subtitleText: nil)
			.frame(height: 150)
	}
}
