import SwiftUI

struct NodeRow: View {
	var node: NodeInfoEntity
	var connected: Bool

	var body: some View {
		VStack(alignment: .leading) {

			HStack {

				CircleText(text: node.user?.shortName ?? "???", color: Color.accentColor).offset(y: 1).padding(.trailing, 5)
					.offset(x: -15)

				if UIDevice.current.userInterfaceIdiom == .pad {
					Text(node.user?.longName ?? "Unknown").font(.headline)
						.offset(x: -15)
				} else {
					Text(node.user?.longName ?? "Unknown").font(.title)
						.offset(x: -15)
				}
			}
			.padding(.bottom, 10)
			
			if connected {
				HStack(alignment: .bottom) {
				
					Image(systemName: "repeat.circle.fill").font(.title3)
						.foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)
					Text("Currently Connected").font(.title3).foregroundColor(Color.accentColor)
				}
				Spacer()
			}
			
			HStack(alignment: .bottom) {

				Image(systemName: "clock.badge.checkmark.fill").font(.title3).foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)

				if UIDevice.current.userInterfaceIdiom == .pad {

					if node.lastHeard != nil {
						Text("Last Heard: \(node.lastHeard!, style: .relative) ago").font(.caption).foregroundColor(.gray)
							.padding(.bottom)
					} else {
						Text("Last Heard: Unknown").font(.caption).foregroundColor(.gray)
					}

				} else {
					
					if node.lastHeard != nil {
						Text("Last Heard: \(node.lastHeard!, style: .relative) ago").font(.subheadline).foregroundColor(.gray)
					} else {
						Text("Last Heard: Unknown").font(.subheadline).foregroundColor(.gray)
					}
				}
			}
		}.padding([.leading, .top, .bottom])
	}
}

struct NodeRow_Previews: PreviewProvider {
	//static var nodes = BLEManager().meshData.nodes

	static var previews: some View {
		Group {
			//NodeRow(node: nodes[0], connected: true)
		}
		.previewLayout(.fixed(width: 300, height: 70))
	}
}
