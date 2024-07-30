import Foundation
import MapKit

enum MapLayer: String, CaseIterable, Equatable, Decodable {
	case standard
	case hybrid
	case satellite
	case offline

	var localized: String {
		self.rawValue.localized
	}
}
