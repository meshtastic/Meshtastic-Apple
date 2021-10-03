import Foundation
import CoreData
import CoreBluetooth
import SwiftUI

//---------------------------------------------------------------------------------------
// Meshtastic BLE Device Manager
//---------------------------------------------------------------------------------------
class BLEHelper: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    var centralManager: CBCentralManager!
    @Published var isSwitchedOn = false
    @Published var peripherals = [Peripheral]()
    
    override init() {
        
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        centralManager.delegate = self
    }
    
    //  Check for Bluetooth Connectivity
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
         if central.state == .poweredOn {
             isSwitchedOn = true
         }
         else {
             isSwitchedOn = false
         }
    }
    
}
