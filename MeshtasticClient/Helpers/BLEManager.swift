import Foundation
import CoreData
import CoreBluetooth
import SwiftUI

//---------------------------------------------------------------------------------------
// Meshtastic BLE Device Manager
//---------------------------------------------------------------------------------------
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // Data
    @ObservedObject private var meshData : MeshData
    @ObservedObject private var messageData : MessageData
    private var centralManager: CBCentralManager!
    @Published var connectedPeripheral: CBPeripheral!
    @Published var peripheralArray = [CBPeripheral]()
    @Published var connectedNodeInfo: Peripheral!
    @Published var connectedNode: NodeInfoModel!
    @Published var lastConnectedNode: String
    //private var rssiArray = [NSNumber]()
    private var timer = Timer()
    private var broadcastNodeId: UInt32 = 4294967295
    
    @Published var isSwitchedOn = false
    @Published var peripherals = [Peripheral]()
    
    var TORADIO_characteristic: CBCharacteristic!
    var FROMRADIO_characteristic: CBCharacteristic!
    var FROMNUM_characteristic: CBCharacteristic!
    
    let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
    let FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")
    
    override init() {
        self.meshData = MeshData()
        self.messageData = MessageData()
        self.lastConnectedNode = ""
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        centralManager.delegate = self
    }

    //---------------------------------------------------------------------------------------
    // Check for Bluetooth Connectivity
    //---------------------------------------------------------------------------------------
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
         if central.state == .poweredOn {
             isSwitchedOn = true
         }
         else {
             isSwitchedOn = false
         }
    }
    /*
     * Scan for nearby BLE devices using the Meshtastic BLE service ID
     */
    func startScanning() {
        
        // Remove Existing Data
        peripherals.removeAll()
        peripheralArray.removeAll()
        //rssiArray.removeAll()
        
        // Start Scanning
        print("Start Scanning")
        centralManager.scanForPeripherals(withServices: [meshtasticServiceCBUUID])
        
    }
        
    //---------------------------------------------------------------------------------------
    // Stop Scanning For BLE Devices
    //---------------------------------------------------------------------------------------
    func stopScanning() {
        
        self.centralManager.stopScan()
        print("Scanning Stopped")
    }
    
    //---------------------------------------------------------------------------------------
    // Connect to a Device via UUID
    //---------------------------------------------------------------------------------------
    func connectToDevice(id: String) {
        cleanup()
        connectedPeripheral = peripheralArray.filter({ $0.identifier.uuidString == id }).first
        
        
        connectedNodeInfo = Peripheral(id: connectedPeripheral.identifier.uuidString, name: connectedPeripheral.name ?? "Unknown", rssi: 0, myInfo: nil)
        lastConnectedNode = id
        self.centralManager?.connect(connectedPeripheral!)
    }
    
    /*
     *  Disconnect Device function
     */
    func disconnectDevice(){
        
       cleanup()
    }
    
    /*
     *  Send Broadcast Message
     */
    public func sendMessage(message: String) -> Bool
    {   var success = true
        if connectedPeripheral == nil || connectedPeripheral!.state != CBPeripheralState.connected {
            success = false
        }
        else {

            let messageModel = MessageModel(messageId: 0, messageTimeStamp: UInt32(Date().timeIntervalSince1970), fromUserId: self.connectedNode.id, toUserId: broadcastNodeId, fromUserLongName: self.connectedNode.user.longName, toUserLongName: "Broadcast", fromUserShortName: self.connectedNode.user.shortName, toUserShortName: "BC", receivedACK: false, messagePayload: message, direction: "OUT")
            let dataType = PortNum.textMessageApp
            let payloadData: Data = message.data(using: String.Encoding.utf8)!
        
            var dataMessage = DataMessage()
            dataMessage.payload = payloadData
            dataMessage.portnum = dataType
            
            var meshPacket = MeshPacket()
            meshPacket.to = broadcastNodeId
            meshPacket.decoded = dataMessage
            meshPacket.wantAck = true
            
            var toRadio: ToRadio!
            toRadio = ToRadio()
            toRadio.packet = meshPacket

            let binaryData: Data = try! toRadio.serializedData()
            if (connectedPeripheral!.state == CBPeripheralState.connected)
            {
                connectedPeripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)

                messageData.messages.append(messageModel)
                messageData.save()

            }
            else
            {
                connectToDevice(id: lastConnectedNode)
            }
            
        }
        return success
    }
    
    //---------------------------------------------------------------------------------------
    // Set Owner function
    //---------------------------------------------------------------------------------------
    public func setOwner(myUser: User)
    {
        var toRadio: ToRadio!
        toRadio = ToRadio()
        //toRadio.setOwner = myUser
        
        let binaryData: Data = try! toRadio.serializedData()
        if (self.connectedPeripheral.state == CBPeripheralState.connected)
        {
            connectedPeripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
            //MasterViewController.shared.DebugPrint2View(text: "Owner set to device" + "\n\r")
        }
        else
        {
            connectToDevice(id: self.connectedPeripheral.identifier.uuidString)
        }
    }
    
        /*
         *  Call this when things either go wrong, or you're done with the connection.
         *  This cancels any subscriptions if there are any, or straight disconnects if not.
         *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
         */
        private func cleanup() {
            // Don't do anything if we're not connected
            guard let connectedPeripheral = connectedPeripheral,
                case .connected = connectedPeripheral.state else { return }
            
            for service in (connectedPeripheral.services ?? [] as [CBService]) {
                for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                    if characteristic.uuid == FROMNUM_UUID && characteristic.isNotifying {
                        // It is notifying, so unsubscribe
                        self.connectedPeripheral?.setNotifyValue(false, for: characteristic)
                    }
                }
            }
            
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
    
    /*
     *  This callback happens whenever a peripheral that is advertising the Meshtastic Service UUID is found.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        // Reject if the signal strength if it is too low
        guard RSSI.intValue >= -100
            else {
                print("Discovered perhiperal not in expected range, at %d", RSSI.intValue)
                return
        }
        print("Discovered %s at %d", String(describing: peripheral.name), RSSI.intValue)
        
        
        
        if peripheralArray.contains(peripheral) {
          print("Duplicate Found.")
        } else {
            print("Adding peripheral: " + ((peripheral.name != nil) ? peripheral.name! : "(null)"));
            peripheralArray.append(peripheral)
            //rssiArray.append(RSSI)
        }
       
        var peripheralName: String!
        peripheralName = peripheral.name
        if peripheral.name == nil {
            if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                peripheralName = name
            }
            else {
                peripheralName = "Unknown"
            }
        }

        let newPeripheral = Peripheral(id: peripheral.identifier.uuidString, name: peripheralName, rssi: RSSI.intValue, myInfo: nil)
        //print(newPeripheral)
        peripherals.append(newPeripheral)
    }
    
    //---------------------------------------------------------------------------------------
    // Connect Peripheral Event
    //---------------------------------------------------------------------------------------
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Peripheral connected: " + peripheral.name!)
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        self.startScanning()
    }
    
    
    /*
     *  If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        
       // print("Failed to connect to \(String(describing: peripheral.name!))", peripheral, String(describing: error))
      //  let errorCode = (error! as! NSError).userInfo
      //  print("Central disconnected because \(errorCode)")
        
        if let e = error {
            let errorDetails = (e as NSError)
            print("Central disconnected because \(errorDetails.localizedDescription)")
        } else {
            print("Central disconnected! (no error)")
        }
        cleanup()
    }
    
    //---------------------------------------------------------------------------------------
    // Disconnect Peripheral Event
    //---------------------------------------------------------------------------------------
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        if let e = error {
            
            print("Central disconnected because \(e)")
          //  connectToDevice(id: peripheral.identifier.uuidString)
        } else {
            print("Central disconnected! (no error)")
        }
        
        if(peripheral.identifier == connectedPeripheral.identifier){
           // connectedPeripheral = nil
          //  connectedNodeInfo = nil
          //  connectedNode = nil
        }
        print("Peripheral disconnected: " + peripheral.name!)
        self.startScanning()
    }
    

    
    //---------------------------------------------------------------------------------------
    // Discover Services Event
    //---------------------------------------------------------------------------------------
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        guard let services = peripheral.services else { return }
                
        for service in services
        {
            print("Service discovered: " + service.uuid.uuidString)
            
            if (service.uuid == meshtasticServiceCBUUID)
            {
                print ("Meshtastic service OK")
                
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    //---------------------------------------------------------------------------------------
    // Discover Characteristics Event
    //---------------------------------------------------------------------------------------
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
      guard let characteristics = service.characteristics else { return }

      for characteristic in characteristics {
        
        switch characteristic.uuid
        {
            case TORADIO_UUID:
                print("TORADIO characteristic OK")
                TORADIO_characteristic = characteristic
                var toRadio: ToRadio = ToRadio()
                toRadio.wantConfigID = 32168
                let binaryData: Data = try! toRadio.serializedData()
                peripheral.writeValue(binaryData, for: characteristic, type: .withResponse)
                break
            
            case FROMRADIO_UUID:
                print("FROMRADIO characteristic OK")
                FROMRADIO_characteristic = characteristic
                peripheral.readValue(for: FROMRADIO_characteristic)
                break
            
            case FROMNUM_UUID:
                print("FROMNUM (Notify) characteristic OK")
                FROMNUM_characteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                break
            
            default:
                break
        }
        
      }
    }
    

    /*
     * Callback lets us know that data has arrived via a notification on the characteristic
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        // Handle Error
        if let error = error {
            print("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        switch characteristic.uuid
        {
            case FROMNUM_UUID:
                peripheral.readValue(for: FROMRADIO_characteristic)
                print(characteristic.value ?? "no value")
            case FROMRADIO_UUID:
                if (characteristic.value == nil || characteristic.value!.isEmpty)
                {
                    return
                }
                //print(characteristic.value ?? "no value")
                //let byteArray = [UInt8](characteristic.value!)
                //print(characteristic.value?.hexDescription ?? "no value")
                var decodedInfo = FromRadio()
                
                decodedInfo = try! FromRadio(serializedData: characteristic.value!)
                //print(decodedInfo)
                
                if decodedInfo.myInfo.myNodeNum != 0
                {
                    print("Save a myInfo")
                    do {
                       print(try decodedInfo.myInfo.jsonString())
                        
                        // Create a MyInfoModel
                        let myInfoModel = MyInfoModel(
                            myNodeNum: decodedInfo.myInfo.myNodeNum,
                            hasGps: decodedInfo.myInfo.hasGps_p,
                            numBands: decodedInfo.myInfo.numBands,
                            maxChannels: decodedInfo.myInfo.maxChannels,
                            firmwareVersion: decodedInfo.myInfo.firmwareVersion,
                            rebootCount: decodedInfo.myInfo.rebootCount,
                            messageTimeoutMsec: decodedInfo.myInfo.messageTimeoutMsec,
                            minAppVersion: decodedInfo.myInfo.minAppVersion)
                        // Save it to the connected nodeInfo
                        connectedNodeInfo.myInfo = myInfoModel
                        // Save it to the connected node
                        connectedNode = meshData.nodes.first(where: {$0.id == decodedInfo.myInfo.myNodeNum})
                        if connectedNode != nil {
                            connectedNode.myInfo = myInfoModel
                            connectedNode.update(from: connectedNode.data)
                        }
                        meshData.save()
                        
                    } catch {
                        fatalError("Failed to decode json")
                    }
                }
                
                if decodedInfo.nodeInfo.num != 0
                {
                    print("Save a nodeInfo")
                    do {
  
                        if meshData.nodes.contains(where: {$0.id == decodedInfo.nodeInfo.num}) {
                            
                            // Found a matching node lets update it
                            let nodeMatch = meshData.nodes.first(where: { $0.id == decodedInfo.nodeInfo.num })
                            if nodeMatch?.lastHeard ?? 0 > decodedInfo.nodeInfo.lastHeard {
                                let nodeIndex = meshData.nodes.firstIndex(where: { $0.id == decodedInfo.nodeInfo.num })
                                meshData.nodes.remove(at: nodeIndex!)
                                meshData.save()
                            }
                            else {
                                
                                // Data is older than what the app already has
                                return
                            }

                        }

                        meshData.nodes.append(
                            NodeInfoModel(
                                num: decodedInfo.nodeInfo.num,
                                user: NodeInfoModel.User(
                                    id: decodedInfo.nodeInfo.user.id,
                                    longName: decodedInfo.nodeInfo.user.longName,
                                    shortName: decodedInfo.nodeInfo.user.shortName,
                                    //macaddr: decodedInfo.nodeInfo.user.macaddr,
                                    hwModel: String(describing: decodedInfo.nodeInfo.user.hwModel)
                                        .uppercased()),
                                
                                position: NodeInfoModel.Position(
                                    latitudeI: decodedInfo.nodeInfo.position.latitudeI,
                                    longitudeI: decodedInfo.nodeInfo.position.longitudeI,
                                    altitude: decodedInfo.nodeInfo.position.altitude,
                                    batteryLevel: decodedInfo.nodeInfo.position.batteryLevel,
                                    time: decodedInfo.nodeInfo.position.time),
                                
                                lastHeard: decodedInfo.nodeInfo.lastHeard,
                                snr: decodedInfo.nodeInfo.snr)
                        )
                        meshData.save()
                            
                        print(try decodedInfo.nodeInfo.jsonString())
                    } catch {
                        fatalError("Failed to decode json")
                    }
                }
                
                if decodedInfo.packet.id  != 0
                {
                    
                    do {

                        if decodedInfo.packet.decoded.portnum == PortNum.textMessageApp {
                            if let messageText = String(bytes: decodedInfo.packet.decoded.payload, encoding: .utf8) {
                                print(messageText)
                                print(try decodedInfo.packet.jsonString())
                                
                                let broadcastNodeId: UInt32 = 4294967295
                                
                                let fromUser = meshData.nodes.first(where: { $0.id == decodedInfo.packet.from })
                                
                                var toUserLongName: String = "Broadcast"
                                var toUserShortName: String = "BC"
                                
                                if decodedInfo.packet.to != broadcastNodeId {
                                    
                                    let toUser = meshData.nodes.first(where: { $0.id == decodedInfo.packet.from })
                                    toUserLongName = toUser?.user.longName ?? "Unknown"
                                    toUserShortName = toUser?.user.shortName ?? "???"
                                }
                                
                                messageData.messages.append(
                                    MessageModel(messageId: decodedInfo.packet.id, messageTimeStamp: decodedInfo.packet.rxTime, fromUserId: decodedInfo.packet.from, toUserId: decodedInfo.packet.to, fromUserLongName: fromUser?.user.longName ?? "Unknown", toUserLongName: toUserLongName, fromUserShortName: fromUser?.user.shortName ?? "???", toUserShortName: toUserShortName, receivedACK: decodedInfo.packet.decoded.wantResponse, messagePayload: messageText, direction: "IN"))
                                messageData.save()
                                
                            } else {
                                print("not a valid UTF-8 sequence")
                            }
                            
                        }
                        else if  decodedInfo.packet.decoded.portnum == PortNum.nodeinfoApp {
                            if let nodeInfoPayload = String(bytes: decodedInfo.packet.decoded.payload, encoding: .unicode) {
                                print(nodeInfoPayload)
                                print(try decodedInfo.packet.jsonString())
                            } else {
                                print("not a valid UTF-8 sequence")
                                print(try decodedInfo.packet.jsonString())
                            }
                            
                        }
                        else if  decodedInfo.packet.decoded.portnum == PortNum.positionApp {
                            if let nodeInfoPayload = String(bytes: decodedInfo.packet.decoded.payload, encoding: .ascii) {
                                print(nodeInfoPayload)
                                print(try decodedInfo.packet.jsonString())
                            } else {
                                print("not a valid UTF-8 sequence")
                                print(try decodedInfo.packet.jsonString())
                            }
                        }
                        else
                        {
                            print("Save a packet")
                            print(try decodedInfo.packet.jsonString())
                        }
                        
                    } catch {
                        fatalError("Failed to decode json")
                    }
                }
                
                if decodedInfo.configCompleteID != 0 {
                    print(decodedInfo)
                    meshData.load()
                    messageData.load()
                }
                
            default:
                print("Unhandled Characteristic UUID: \(characteristic.uuid)")
        }
        
        peripheral.readValue(for: FROMRADIO_characteristic)
    }
}


