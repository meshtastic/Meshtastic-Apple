import Foundation

struct MyInfoModel: Identifiable, Codable {
    
    // Uses the BLE Peripheral identifier as the ID
    // So myInfo can map between Peripherals and Nodes
    var id: UInt32
    var myNodeNum: UInt32
    var hasGps: Bool
    var numBands: UInt32
    var maxChannels: UInt32
    var firmwareVersion: String
    var messageTimeoutMsec: UInt32
    var minAppVersion: UInt32
    
    init(myNodeNum: UInt32, hasGps: Bool, numBands: UInt32, maxChannels: UInt32, firmwareVersion: String, messageTimeoutMsec: UInt32, minAppVersion: UInt32) {
        
        self.id = myNodeNum
        self.myNodeNum = myNodeNum
        self.hasGps = hasGps
        self.numBands = numBands
        self.maxChannels = maxChannels
        self.firmwareVersion = firmwareVersion
        self.messageTimeoutMsec = messageTimeoutMsec
        self.minAppVersion = minAppVersion
    }
}
