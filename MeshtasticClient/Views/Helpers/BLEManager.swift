import Foundation
import CoreBluetooth

struct Peripheral: Identifiable {
    let id: Int
    let name: String
    let rssi: Int
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    
    var myCentral: CBCentralManager!
    private var meshtasticPeripheral: CBPeripheral!
    @Published var isSwitchedOn = false
    @Published var peripherals = [Peripheral]()
    
    let meshtasticServiceID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
    let FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453") //Notify
    
    override init() {
        super.init()
 
        myCentral = CBCentralManager(delegate: self, queue: nil)
        myCentral.delegate = self
        
    }


    func centralManagerDidUpdateState(_ central: CBCentralManager) {
         if central.state == .poweredOn {
             isSwitchedOn = true
         }
         else {
             isSwitchedOn = false
         }
    }


    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        print(peripheral)

        var peripheralName: String!
       
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            peripheralName = name
        }
        else {
            peripheralName = "Unknown"
        }
       
        let newPeripheral = Peripheral(id: peripherals.count, name: peripheralName, rssi: RSSI.intValue)
        print(newPeripheral)
        peripherals.append(newPeripheral)
    }
    
    func startScanning() {
         print("startScanning")
         peripherals = [];
         myCentral.scanForPeripherals(withServices: [meshtasticServiceID])
     }
    
    func stopScanning() {
        print("stopScanning")
        myCentral.stopScan()
    }
    
    func connectToDevice(uuid:String) {
        
      //  let meshtasticPeripheral = self.peripherals.first(where: { $0.id == uuid })
            if (meshtasticPeripheral == nil) {
              return
            }
        // Attempt to connect to this device
         myCentral.connect(meshtasticPeripheral, options: nil)

         // Retain the peripheral
      
    }
    
    
}
