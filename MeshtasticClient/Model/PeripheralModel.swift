import Foundation
import CoreBluetooth

final class Peripheral: Identifiable {
    var id: String
    var name: String
    var rssi: Int
    var peripheral: CBPeripheral
    
    var myInfo: MyInfoModel?
    
    init(id: String, name: String, rssi: Int, peripheral: CBPeripheral, myInfo: MyInfoModel?) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.peripheral = peripheral
        self.myInfo = myInfo
    }
}
