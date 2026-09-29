import SwiftUI

/// iOS 17 inputs for "was the reader at the bottom when this reload started".
/// Not observed: the scroll callback writes these every frame, and the list
/// reads them only from `loadMessages`. `@State` holds the reference, so
/// property writes do not rebuild the message list.
final class MessageScrollTracker {
	var bottomMarkerY: CGFloat = .infinity
	var viewportHeight: CGFloat = 0

	var isNearBottom: Bool {
		bottomMarkerY <= viewportHeight + 24
	}

	/// iOS 17 scrolls the list itself. iOS 18 follows through `scrollPosition`.
	static var usesLegacyBottomScroll: Bool {
		if #available(iOS 18.0, macOS 15.0, *) {
			false
		} else {
			true
		}
	}

	/// A reload scrolls only on the legacy path, and only when the reader was
	/// already at the bottom and the last row changed. `nearBottomBeforeFetch`
	/// is the sample taken before the fetch: new rows move the marker.
	static func shouldFollowReload(
		legacyScroll: Bool = usesLegacyBottomScroll,
		nearBottomBeforeFetch: Bool,
		previousLastID: Int64?,
		newLastID: Int64?
	) -> Bool {
		legacyScroll && nearBottomBeforeFetch && newLastID != previousLastID
	}

	/// A send always returns to the bottom. On the legacy path the reload may
	/// already have requested that scroll; don't request it twice.
	static func shouldFollowSend(
		legacyScroll: Bool = usesLegacyBottomScroll,
		scrollRequestChangedDuringLoad: Bool
	) -> Bool {
		if legacyScroll {
			return !scrollRequestChangedDuringLoad
		}
		return true
	}
}

extension View {
	@ViewBuilder
	func messageBottomScrollPosition(request: Int) -> some View {
		if #available(iOS 18.0, macOS 15.0, *) {
			modifier(MessageBottomScrollPositionModifier(request: request))
		} else {
			self
		}
	}

	/// On iOS 17, measure the bottom marker in the scroll view's coordinate space.
	@ViewBuilder
	func trackMessageBottomPosition(_ tracker: MessageScrollTracker) -> some View {
		if #available(iOS 18.0, macOS 15.0, *) {
			self
		} else {
			background {
				GeometryReader { geometry in
					Color.clear
						.onAppear {
							tracker.bottomMarkerY = geometry.frame(in: .named("messageScroll")).maxY
						}
						.onChange(of: geometry.frame(in: .named("messageScroll")).maxY) { _, value in
							tracker.bottomMarkerY = value
						}
						.onDisappear { tracker.bottomMarkerY = .infinity }
				}
			}
		}
	}

	@ViewBuilder
	func trackMessageScrollViewport(_ tracker: MessageScrollTracker) -> some View {
		if #available(iOS 18.0, macOS 15.0, *) {
			self
		} else {
			coordinateSpace(name: "messageScroll")
				.background {
					GeometryReader { geometry in
						Color.clear
							.onAppear { tracker.viewportHeight = geometry.size.height }
							.onChange(of: geometry.size.height) { _, value in
								tracker.viewportHeight = value
							}
					}
				}
		}
	}
}

@available(iOS 18.0, macOS 15.0, *)
private struct MessageBottomScrollPositionModifier: ViewModifier {
	let request: Int
	// An edge position follows later content growth once a sent message returns us to the bottom.
	@State private var position = ScrollPosition(edge: .bottom)

	func body(content: Content) -> some View {
		content
			.scrollPosition($position)
			.onChange(of: request) {
				position.scrollTo(edge: .bottom)
			}
	}
}
