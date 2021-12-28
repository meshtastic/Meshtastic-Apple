import Foundation
import SwiftUI
import CoreBluetooth

struct Channels: View {

	@State private var isShowingDetailView = true

    var body: some View {

        NavigationView {

			NavigationLink(destination: Messages(), isActive: $isShowingDetailView) {

				List {

					HStack {

						Image(systemName: "dial.max.fill")
							.font(.system(size: 62))
							.symbolRenderingMode(.hierarchical)
							.padding(.trailing)
							.foregroundColor(.accentColor)

						Text("All - Broadcast")
							.font(.largeTitle)

					}.padding()
				}
            }
            .navigationTitle("Contacts")
        }
		.navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}

struct MessageList_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            Channels()
        }
    }
}
