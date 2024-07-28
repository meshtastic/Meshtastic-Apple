import SwiftUI

struct LastHeardText: View {
	var lastHeard: Date?

	@ViewBuilder
	var body: some View {
		if let lastHeard, lastHeard.timeIntervalSince1970 > 0 {
			Text(lastHeard.formatted())
		} else {
			Text("N/A")
		}
	}
}
