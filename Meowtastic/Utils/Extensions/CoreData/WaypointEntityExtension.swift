import CoreData
import CoreLocation
import MapKit
import SwiftUI

struct WaypointCoordinate: Identifiable {
	let id: UUID
	let coordinate: CLLocationCoordinate2D?
	let waypointId: Int64
}

extension WaypointEntity {
	var latitude: Double? {
		let d = Double(latitudeI)
		if d == 0 {
			return 0
		}

		return d / 1e7
	}

	var longitude: Double? {
		let d = Double(longitudeI)
		if d == 0 {
			return 0
		}

		return d / 1e7
	}

	var waypointCoordinate: CLLocationCoordinate2D? {
		if let latitude, let longitude, latitudeI != 0, longitudeI != 0 {
			return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
		}
		else {
			return nil
		}
	}

	var annotaton: MKPointAnnotation {
		let pointAnn = MKPointAnnotation()
		if let waypointCoordinate {
			pointAnn.coordinate = waypointCoordinate
		}

		return pointAnn
	}

	static func allWaypointssFetchRequest() -> NSFetchRequest<WaypointEntity> {
		let request: NSFetchRequest<WaypointEntity> = WaypointEntity.fetchRequest()
		request.fetchLimit = 50
		request.returnsDistinctResults = true
		request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: false)]
		request.predicate = NSPredicate(format: "expire == nil || expire >= %@", Date() as NSDate)

		return request
	}
}

extension WaypointEntity: MKAnnotation {
	public var coordinate: CLLocationCoordinate2D {
		waypointCoordinate ?? LocationManager.defaultLocation.coordinate
	}

	public var title: String? { name ?? "Dropped Pin" }

	public var subtitle: String? {
		(longDescription ?? "") +
		String(expire != nil ? "\n⌛ Expires \(String(describing: expire?.formatted()))" : "") +
		String(locked > 0 ? "\n🔒 Locked" : "")
	}
}
