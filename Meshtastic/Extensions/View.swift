//
//  View.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/14/24.
//

import SwiftUI

public extension View {
	func onFirstAppear(_ action: @escaping () -> Void) -> some View {
		modifier(FirstAppear(action: action))
	}
}

private struct FirstAppear: ViewModifier {
	let action: () -> Void

	// Use this to only fire your block one time
	@State private var hasAppeared = false

	func body(content: Content) -> some View {
		// And then, track it here
		content.onAppear {
			guard !hasAppeared else { return }
			hasAppeared = true
			action()
		}
	}
}
