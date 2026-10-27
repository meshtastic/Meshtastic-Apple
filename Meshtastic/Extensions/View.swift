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

	/// A close button in the toolbar's cancel position, on every platform. A sheet can't be swiped
	/// away on Mac or Vision Pro, so each one needs a way out it can show. Apply it to the root view
	/// inside the sheet's `NavigationStack`; `action` replaces the plain dismiss when closing has
	/// to do something first.
	func sheetCloseButton(action: (() -> Void)? = nil) -> some View {
		modifier(SheetCloseButton(action: action))
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
	func defaultScrollAnchorBottomSizeChanges() -> some View {
		if #available(iOS 18, macOS 15, *) {
			self.defaultScrollAnchor(.bottom, for: .sizeChanges)
		} else {
			self
		}
	}

	@ViewBuilder func `if`<Content: View>(_ condition: @autoclosure () -> Bool, transform: (Self) -> Content) -> some View {
		if condition() {
			transform(self)
		} else {
			self
		}
	}

	/// Standard capsule-shaped prominent button styling.
	@ViewBuilder
	func capsuleButtonStyle() -> some View {
		self
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.horizontal)
			.buttonStyle(.borderedProminent)
			.tint(.accentFill)
	}

	@ViewBuilder
	func glassButtonStyle() -> some View {
		if #available(iOS 26.0, macOS 26.0, *) {
			glassButtonStyleOS26()
		} else {
			self
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
		}
	}

	@available(iOS 26.0, macOS 26.0, *)
	@ViewBuilder
	private func glassButtonStyleOS26() -> some View {
		#if os(visionOS)
		// White like the tab bar's icons; a bordered button draws its label in the accent color.
		self.buttonStyle(.bordered).tint(.white)
		#else
		self.buttonStyle(.glass)
		#endif
	}
}

/// How a scroll dismisses the keyboard. Our own type because SwiftUI's `ScrollDismissesKeyboardMode`
/// doesn't exist on visionOS, where there is no on-screen keyboard to dismiss.
enum KeyboardScrollDismissal {
	case immediately, interactively
}

extension View {
	/// `.scrollDismissesKeyboard`, as a no-op on visionOS.
	func dismissesKeyboardOnScroll(_ mode: KeyboardScrollDismissal = .immediately) -> some View {
		#if os(visionOS)
		self
		#else
		self.scrollDismissesKeyboard(mode == .immediately ? .immediately : .interactively)
		#endif
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

private struct SheetCloseButton: ViewModifier {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.presentationHost) private var host
	let action: (() -> Void)?

	func body(content: Content) -> some View {
		// In a panel the "sheet" is a push and already has a back button.
		switch host {
		case .window: closeButton(content)
		case .panel: content
		}
	}

	private func closeButton(_ content: Content) -> some View {
		content.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button {
					if let action { action() } else { dismiss() }
				} label: {
					Image(systemName: "xmark")
				}
				.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
			}
		}
	}
}
