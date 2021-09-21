/*
See LICENSE folder for this sample’s licensing information.
*/
import SwiftUI
import CoreLocation

struct NodeInfoModel: Identifiable, Codable {
    
    let id: UUID
    var num: UInt32
    
    var user: User
    struct User: Identifiable, Codable {
        var id: String
        var longName: String
        var shortName: String
        var hwModel: String
        
        init(id: String, longName: String, shortName: String, hwModel: String) {
            self.id = id
            self.longName = longName
            self.shortName = shortName
            self.hwModel = hwModel
        }
    }
    var position: Position
    struct Position: Codable {
        var latitudeI: Int32?
        var latitude: Double? {
            if let unwrappedLat = latitudeI {
                let d = Double(unwrappedLat)
                
                return d / 1e7
            }
            else {
               return nil
            }
        }
        var longitudeI: Int32?
        var longitude: Double? {
            if let unwrappedLong = longitudeI {
                let d = Double(unwrappedLong)
                
                return d / 1e7
            }
            else {
               return nil
            }
        }
        var coordinate: CLLocationCoordinate2D? {
            if longitude != nil {
                let coord = CLLocationCoordinate2D(latitude: latitude!, longitude: longitude!)
                
                return coord
            }
            else {
               return nil
            }
        }
        var altitude: Int32?
        var batteryLevel: Int32?
        var time: Int32?
        
        init(latitudeI: Int32?, longitudeI: Int32?, altitude: Int32?, batteryLevel: Int32?, time: Int32? ) {
            self.latitudeI = latitudeI
            self.longitudeI = longitudeI
            self.altitude = altitude
            self.batteryLevel = batteryLevel
            self.time = time
        }
    }
    
    var lastHeard: Double
    var snr: Double?


    init(id: UUID = UUID(), num: UInt32, user: User, position: Position, lastHeard: Double, snr: Double?) {
        self.id = id
        self.num = num
        self.user = user
        self.position = position
        self.lastHeard = lastHeard
        self.snr = snr
    }
}

extension NodeInfoModel {
    //var user = User(id: "!a66c166f", longName: "RAK Solar 2", shortName: "RS2", macaddr:"8eambBZv", hwModel:"RAK4631")
    //let position = Position(batteryLevel: 68)
    static var data: [NodeInfoModel] {
        [

            NodeInfoModel(num: 2792101487, user: User(id: "!a66c166f", longName: "RAK Solar 2", shortName: "RS2", hwModel: "RAK4631"), position: Position(latitudeI:nil, longitudeI: nil, altitude: nil, batteryLevel: 68, time: nil),  lastHeard: 1631593661, snr: nil),
            NodeInfoModel(num: 1000569662, user: User(id: "!3ba37b3e", longName: "RAK Solar 1", shortName: "RS1", hwModel: "RAK4631"), position: Position(latitudeI:476021390, longitudeI: -1221532609, altitude: 71, batteryLevel: 70, time: 1629314497),  lastHeard: 1629392801, snr: 5.25)


        ]
    }
}

extension NodeInfoModel {
    struct Data {
        var num: UInt32 = 0
        var user: User
        var postion: Position
        var lastHeard: Double
        var snr: Double?
        
    }

    var data: Data {
        return Data(num: num, user: user, postion: position, lastHeard: lastHeard, snr: snr)
    }

    mutating func update(from data: Data) {
        num = data.num
        user = data.user
        position = data.postion
        lastHeard = data.lastHeard
        snr = data.snr
    }
}
