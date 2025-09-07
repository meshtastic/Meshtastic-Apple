//
//  View.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/14/24.
//

import SwiftUI

extension View {
	func onFirstAppear(_ action: @escaping () -> Void) -> some View {
		modifier(FirstAppear(action: action))
	}
	
	@ViewBuilder func olderThanOS26( _ contentBuilder: (@escaping (Self) -> some View) ) -> some View {
		if #available(iOS 26.0, macOS 26.0, *) {
			self
		} else {
			contentBuilder(self)
		}
	}
	/// Conditionally applies `defaultScrollAnchor` only on iOS 18+.
	@ViewBuilder
	func defaultScrollAnchorTopAlignment() -> some View {
		if #available(iOS 18, macOS 15, *) {
			AnyView(self.defaultScrollAnchor(.top, for: .alignment))
		} else {
			AnyView(self)
		}
	}
	
	/// Conditionally applies `defaultScrollAnchor` only on iOS 18+.
	@ViewBuilder
	func defaultScrollAnchorBottomSizeChanges() -> some View {
		if #available(iOS 18, macOS 15, *) {
			AnyView(self.defaultScrollAnchor(.bottom, for: .sizeChanges))
		} else {
			AnyView(self)
		}
	}

	@ViewBuilder func `if`<Content: View>(_ condition: @autoclosure () -> Bool, transform: (Self) -> Content) -> some View {
		if condition() {
			transform(self)
		} else {
			self
		}
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
