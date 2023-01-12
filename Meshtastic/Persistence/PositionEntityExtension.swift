import CoreData
import CoreLocation
import MapKit
import SwiftUI

extension PositionEntity {

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

	var nodeCoordinate: CLLocationCoordinate2D? {
		if latitudeI != 0 && longitudeI != 0 {
			let coord = CLLocationCoordinate2D(latitude: latitude!, longitude: longitude!)
			return coord
		} else {
		   return nil
		}
	}
	
	var annotaton: MKPointAnnotation {
		let pointAnn = MKPointAnnotation()
		if nodeCoordinate != nil {
			pointAnn.coordinate = nodeCoordinate!
		}
		return pointAnn
	}
}

extension PositionEntity: MKAnnotation {
	public var coordinate: CLLocationCoordinate2D { nodeCoordinate ?? CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0) }
	public var title: String? {  nodePosition?.user?.shortName ?? NSLocalizedString("unknown", comment: "Unknown") }
	public var subtitle: String? {  time?.formatted() }
}
