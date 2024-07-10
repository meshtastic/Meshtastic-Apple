import MapKit
import OSLog
import SwiftUI

struct MapSnapshotView: View {
	let location: CLLocationCoordinate2D
	var span: CLLocationDegrees = 0.005

	@State
	private var snapshotImage: Result<UIImage, Error>?

    var body: some View {
		GeometryReader { geometry in
			Group {
				switch snapshotImage {
				case .success(let image):
					Image(uiImage: image)
				case .failure(let error):
					if #available(iOS 17.0, *) {
						ContentUnavailableView {
							Label {
								Text(error.localizedDescription)
							} icon: {
								Image(systemName: "mappin.slash")
							}
						}
					} else {
						Label {
							Text(error.localizedDescription)
						} icon: {
							Image(systemName: "mappin.slash")
						}
					}
				case nil:
					VStack {
						Spacer()
						HStack {
							Spacer()
							ProgressView()
								.progressViewStyle(CircularProgressViewStyle())
							Spacer()
						}
						Spacer()
					}
				}
			}.onAppear {
				generateSnapshot(size: geometry.size)
			}
		}
    }

	private func generateSnapshot(
		size: CGSize
	) {
		// The region the map should display.
		let region = MKCoordinateRegion(
			center: self.location,
			span: MKCoordinateSpan(
				latitudeDelta: self.span,
				longitudeDelta: self.span
			)
		)

		// Map options.
		let mapOptions = MKMapSnapshotter.Options()
		mapOptions.region = region
		mapOptions.size = size
		mapOptions.showsBuildings = true

		// Create the snapshotter and run it.
		let snapshotter = MKMapSnapshotter(options: mapOptions)
		snapshotter.start { snapshot, error in
			if let error {
				Logger.services.error("Failed to generate map snapshot for node details: \(error.localizedDescription)")
				self.snapshotImage = .failure(error)
			} else if let snapshot {
				self.snapshotImage = .success(snapshot.image)
			}
		}
	}
}
