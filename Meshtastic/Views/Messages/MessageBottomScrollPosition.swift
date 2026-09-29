import SwiftUI

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
	func trackMessageBottomPosition(_ bottomY: Binding<CGFloat>) -> some View {
		if #available(iOS 18.0, macOS 15.0, *) {
			self
		} else {
			background {
				GeometryReader { geometry in
					Color.clear
						.onAppear {
							bottomY.wrappedValue = geometry.frame(in: .named("messageScroll")).maxY
						}
						.onChange(of: geometry.frame(in: .named("messageScroll")).maxY) { _, value in
							bottomY.wrappedValue = value
						}
						.onDisappear { bottomY.wrappedValue = .infinity }
				}
			}
		}
	}

	@ViewBuilder
	func trackMessageScrollViewport(_ height: Binding<CGFloat>) -> some View {
		if #available(iOS 18.0, macOS 15.0, *) {
			self
		} else {
			coordinateSpace(name: "messageScroll")
				.background {
					GeometryReader { geometry in
						Color.clear
							.onAppear { height.wrappedValue = geometry.size.height }
								.onChange(of: geometry.size.height) { _, value in
									height.wrappedValue = value
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
