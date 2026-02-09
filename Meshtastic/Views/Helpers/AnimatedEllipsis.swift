import SwiftUI

struct AnimatedEllipsis: View {
	var body: some View {
		TimelineView(.periodic(from: .now, by: 0.45)) { context in
			let ticks = Int(context.date.timeIntervalSinceReferenceDate / 0.45)
			let dotCount = (ticks % 3) + 1
			Text(String(repeating: ".", count: dotCount))
				.monospacedDigit()
		}
	}
}
