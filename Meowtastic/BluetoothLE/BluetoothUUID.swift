import CoreBluetooth

enum BluetoothUUID {
    static let meshtasticService = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    static let toRadio = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
    static let fromRadio = CBUUID(string: "0x2C55E69E-4993-11ED-B878-0242AC120002")
    static let fromRadioEOL = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    static let fromNum = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")
    static let logRadio = CBUUID(string: "0x5a3d6e49-06e6-4423-9944-e9de8cdf9547")
    static let logRadioLegacy = CBUUID(string: "0x6C6FD238-78FA-436B-AACF-15C5BE1EF2E2")
}
