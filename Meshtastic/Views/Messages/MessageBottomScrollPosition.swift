import SwiftUI

/// Inputs for "was the reader at the bottom when this reload started".
/// Not observed: the scroll callbacks write these every frame, and the list
/// reads them only from `loadMessages`. `@State` holds the reference, so
/// property writes do not rebuild the message list.
final class MessageScrollTracker {
	/// iOS 17: the bottom marker's position and the viewport height.
	var bottomMarkerY: CGFloat = .infinity
	var viewportHeight: CGFloat = 0
	/// iOS 18 and later: set from the scroll geometry.
	var scrolledToBottom: Bool?

	var isNearBottom: Bool {
		scrolledToBottom ?? (bottomMarkerY <= viewportHeight + 24)
	}

	/// A reload scrolls only when the reader was already at the bottom and the
	/// last row changed. `nearBottomBeforeFetch` is the sample taken before the
	/// fetch: new rows move the bottom.
	static func shouldFollowReload(
		nearBottomBeforeFetch: Bool,
		previousLastID: Int64?,
		newLastID: Int64?
	) -> Bool {
		nearBottomBeforeFetch && newLastID != previousLastID
	}

	/// A send always returns to the bottom. The reload may already have
	/// requested that scroll; don't request it twice.
	static func shouldFollowSend(scrollRequestChangedDuringLoad: Bool) -> Bool {
		!scrollRequestChangedDuringLoad
	}
}

extension View {
	@ViewBuilder
	func messageBottomScrollPosition(request: Int, tracker: MessageScrollTracker) -> some View {
		if #available(iOS 18.0, macOS 15.0, *) {
			modifier(MessageBottomScrollPositionModifier(request: request, tracker: tracker))
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
	let tracker: MessageScrollTracker
	@State private var position = ScrollPosition(edge: .bottom)

	func body(content: Content) -> some View {
		content
			.scrollPosition($position)
			.onScrollGeometryChange(for: Bool.self) { geometry in
				geometry.visibleRect.maxY >= geometry.contentSize.height - 24
			} action: { _, atBottom in
				tracker.scrolledToBottom = atBottom
			}
			.onChange(of: request) {
				position.scrollTo(edge: .bottom)
			}
	}
}
