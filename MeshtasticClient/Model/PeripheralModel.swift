import Foundation

final class Peripheral: Identifiable {
    var id: String
    var name: String
    var rssi: Int
    
    var myInfo: MyInfoModel?
    
    init(id: String, name: String, rssi: Int, myInfo: MyInfoModel?) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.myInfo = myInfo
    }
}
