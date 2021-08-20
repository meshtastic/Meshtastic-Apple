/*
See LICENSE folder for this app’s licensing information.

Abstract:
A representation of a single device.
*/

import Foundation
import SwiftUI
import CoreLocation

struct Device: Hashable, Codable, Identifiable {
    
    var longName: String
    var shortName: String
    var id: String
    var region: String
    var hasGPS: Bool
    var isRouter: Bool
    var firmwareVersion: String
    var hardwareModel: String
    var lastHeard: Double
    var snr: Double
    
    private var imageName: String
    var image: Image {
        Image(imageName)
    }
    
    var position: Position

    struct Position: Hashable, Codable {
        var latitude: Double
        var longitude: Double
        var altitude: Int
        var batteryLevel: Int    }
}
