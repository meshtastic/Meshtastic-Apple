import SwiftUI

struct TileDownloadStatus: View {
	@ObservedObject var tileManager = OfflineTileManager.shared

	var body: some View {
		if tileManager.status == .downloading {
			Image(systemName: "arrow.down.circle.fill")
				.foregroundColor(.gray)
		} else {
			EmptyView()
		}
	}
}
