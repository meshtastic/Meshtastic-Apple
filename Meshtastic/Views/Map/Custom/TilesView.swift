//
//  TilesView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen on 5/6/23.
//

import SwiftUI
import MapKit

struct TilesView: View {
	
	@ObservedObject var tileManager = OfflineTileManager.shared
	@State var totalDownloadedTileSize = ""
	
	var body: some View {
		
		Button(action: {
			tileManager.removeAll()
			totalDownloadedTileSize = tileManager.getAllDownloadedSize()
			print("delete all tiles")
		}) {
			
			HStack {
				Image(systemName: "trash")
					.foregroundColor(.red)
				Text("\("map.tiles.delete".localized) (\(totalDownloadedTileSize))")
					.foregroundColor(.red)
				Spacer()
			}
		}
		.onAppear(perform: {
			totalDownloadedTileSize = tileManager.getAllDownloadedSize()
		})
		Divider()
	}
}

// MARK: Previews
struct TilesView_Previews: PreviewProvider {
		
	static var previews: some View {
		
		TilesView()
			.previewLayout(.fixed(width: 300, height: 80))
			.environment(\.colorScheme, .light)
	}
}
