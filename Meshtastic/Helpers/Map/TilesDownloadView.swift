//
//  TilesDownloadView.swift
//  Meshtastic
//
//  Copyright © Garth Vander Houwen 5/5/23.
//

import SwiftUI
import MapKit

struct TilesDownloadView: View {
	
	@ObservedObject var tileManager = OfflineTileManager.shared
	@State private var showAlert = false
	@State var otherDownloadInProgress = false
	
	var boundingBox: MKMapRect
	var name: String
	
	
	var body: some View {
		
		Button(action: {
			if self.tileManager.status == .download {
				//Feedback.selected()
				self.tileManager.download(boundingBox: self.boundingBox, name: self.name)
			} else if self.tileManager.status == .downloaded {
				//Feedback.selected()
				self.showAlert = true
			}
		}) {
			HStack() {
				if tileManager.status == .downloaded {
					Image(systemName: "trash")
					.accentColor(.red)
				} else {
					Image(systemName: "map")
				}
				
				VStack(alignment: .leading) {
					if tileManager.status == .download {
						Text("\("map.tiles.download".localized) (\(tileManager.getEstimatedDownloadSize(for: boundingBox).toBytes))")
					} else if tileManager.status == .downloading {
						Text("\("map.tiles.downloading".localized) (\(tileManager.getEstimatedDownloadSize(for: boundingBox).toBytes) \("Left".localized))")
					} else {
						Text("\("map.tiles.delete".localized) (\(tileManager.getDownloadedSize(for: boundingBox).toBytes))")
						.accentColor(.red)
					}
					if tileManager.status == .downloading {
						ProgressView(value: tileManager.progress)
							.frame(height: 10)
					}
				}
				Spacer()
			}
			//.isHidden(otherDownloadInProgress, remove: true)
		}
		.onAppear {
			guard self.tileManager.status != .downloading else {
				self.otherDownloadInProgress = true
				return
			}
			self.tileManager.status = self.tileManager.hasBeenDownloaded(for: self.boundingBox) ? .downloaded : .download
		}
		.actionSheet(isPresented: $showAlert) {
			ActionSheet(
				title: Text("\("Delete".localized) (\(self.tileManager.getDownloadedSize(for: boundingBox).toBytes))"),
				message: Text("DeleteTiles".localized),
				buttons: [
					.destructive(Text("Delete".localized), action: { self.tileManager.remove(for: self.boundingBox) }),
					.cancel(Text("Cancel".localized))
				]
			)
		}
	}
}

// MARK: Previews
struct TilesRow_Previews: PreviewProvider {
		
	static var previews: some View {
		
		TilesDownloadView(boundingBox: MKMapRect(), name: "test")
			.previewLayout(.fixed(width: 300, height: 80))
			.environment(\.colorScheme, .light)
	}
}
