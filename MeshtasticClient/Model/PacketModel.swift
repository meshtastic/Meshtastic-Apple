struct PacketModel: Identifiable {
    
    var id: UInt32
    var from: UInt32
    var to: UInt32
    var channel: UInt32
    var rxTime: UInt32
    var hopLimit: UInt32
    var wantAck: Bool

    
    init(id: UInt32, from: UInt32, to: UInt32, channel: UInt32, rxTime: UInt32, hopLimit: UInt32, wantAck: Bool) {
        
        self.id = id
        self.from = from
        self.to = to
        self.channel = channel
        self.rxTime = rxTime
        self.hopLimit = hopLimit
        self.wantAck = wantAck
    }
}
