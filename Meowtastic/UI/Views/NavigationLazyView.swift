import SwiftUI

struct NavigationLazyView<Content: View>: View {
	let build: () -> Content

	var body: Content {
		build()
	}

	init(_ build: @autoclosure @escaping () -> Content) {
		self.build = build
	}
}
