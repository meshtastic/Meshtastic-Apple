//
//  MapLocation.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 12/17/21.
//
import Foundation
import MapKit

struct MapLocation: Identifiable {

	  let id = UUID()
	  let name: String
	  let coordinate: CLLocationCoordinate2D
}
