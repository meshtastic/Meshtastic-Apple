import CoreData
import CoreLocation
import MapKit
import MeshtasticProtobufs

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
			return CLLocationCoordinate2D(latitude: latitude!, longitude: longitude!)
		}
		
		return nil
	}
	
	var nodeLocation: CLLocation? {
		if latitudeI != 0 && longitudeI != 0 {
			return CLLocation(latitude: latitude!, longitude: longitude!)
		}
		
		return nil
	}
	
	var annotaton: MKPointAnnotation {
		let pointAnn = MKPointAnnotation()
		
		if nodeCoordinate != nil {
			pointAnn.coordinate = nodeCoordinate!
		}
		return pointAnn
	}
	
	static func allPositionsFetchRequest() -> NSFetchRequest<PositionEntity> {
		let request: NSFetchRequest<PositionEntity> = PositionEntity.fetchRequest()
		request.fetchLimit = 1000
		request.returnsObjectsAsFaults = false
		request.includesSubentities = true
		request.returnsDistinctResults = true
		request.sortDescriptors = [NSSortDescriptor(key: "time", ascending: false)]
		
		let positionPredicate = NSPredicate(
			format: "nodePosition != nil && (nodePosition.user.shortName != nil || nodePosition.user.shortName != '') && latest == true"
		)
		
		if let lastKnownLocation = LocationManager.shared.lastKnownLocation {
			let d: Double = UserDefaults.meshMapDistance * 1.1
			let r: Double = 6371009
			
			let meanLatitidue = lastKnownLocation.coordinate.latitude * .pi / 180
			let deltaLatitude = d / r * 180 / .pi
			let deltaLongitude = d / (r * cos(meanLatitidue)) * 180 / .pi
			
			let minLatitude: Double = lastKnownLocation.coordinate.latitude - deltaLatitude
			let maxLatitude: Double = lastKnownLocation.coordinate.latitude + deltaLatitude
			let minLongitude: Double = lastKnownLocation.coordinate.longitude - deltaLongitude
			let maxLongitude: Double = lastKnownLocation.coordinate.longitude + deltaLongitude
			
			let distancePredicate = NSPredicate(
				format: "(%lf <= (longitudeI / 1e7)) AND ((longitudeI / 1e7) <= %lf) AND (%lf <= (latitudeI / 1e7)) AND ((latitudeI / 1e7) <= %lf)",
				minLongitude,
				maxLongitude,
				minLatitude,
				maxLatitude
			)
			
			request.predicate = NSCompoundPredicate(
				type: .and,
				subpredicates: [positionPredicate, distancePredicate]
			)
		}
		else {
			request.predicate = positionPredicate
		}

		return request
	}
}

extension PositionEntity: MKAnnotation {
	public var coordinate: CLLocationCoordinate2D {
		nodeCoordinate ?? LocationManager.defaultLocation.coordinate
	}

	public var title: String? {
		nodePosition?.user?.shortName ?? "unknown".localized
	}

	public var subtitle: String? {
		time?.formatted()
	}
}
