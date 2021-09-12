/*
See LICENSE folder for this app’s licensing information.

Abstract:
A representation of a single device.
*/

import Foundation
import SwiftUI
import CoreLocation

struct Device2: Hashable, Codable, Identifiable {

    var id: String
    var num: Int32
    
    struct MyInfo: Hashable, Codable {
        
        var hasGps: Bool
        var numBands: Int32
        var maxChannels: Int32
        var firmwareVersion: String
        var rebootCount: Int32
        var messageTimeoutMsec: Int32
        var minAppVersion: Int32
    }
    
    
    struct User: Hashable, Codable {
        var id: String
        var longName: String
        var shortName: String
        var macaddr: String
        var hwModel: String
    }
    
    struct Position: Hashable, Codable {
        var latitude: Int32
        var longitude: Int32
        var altitude: Int32
        var batteryLevel: Int
    }
    var lastHeard: Int32
    
}
