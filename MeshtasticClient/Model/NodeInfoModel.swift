//
//  NodeInfo.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 9/13/21.
//

import Foundation
import SwiftUI
import CoreLocation

struct NodeInfoModel: Hashable, Codable, Identifiable {
    
    let id = UUID()
    var num: UInt32
    
    var user: User
    struct User: Hashable, Codable, Identifiable {
        var id: String
        var longName: String
        var shortName: String
        var macaddr: String
        var hwModel: String
    }
    
    var position: Position
    struct Position: Hashable, Codable {
        var latitudeI: Int32?
        var longitudeI: Int32?
        var altitude: Int32?
        var batteryLevel: Int32?
        var time: Int32?
    }
    
    var lastHeard: Double
    var snr: Double?
}
