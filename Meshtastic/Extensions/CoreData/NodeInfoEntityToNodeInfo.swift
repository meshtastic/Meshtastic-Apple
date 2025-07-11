// NodeInfoEntityToNodeInfo.swift
// Meshtastic
//
// Utility to convert NodeInfoEntity (Core Data) to NodeInfo (protobuf)

import Foundation
import MeshtasticProtobufs

extension NodeInfoEntity {
    func toProto() -> NodeInfo {
        var userProto = User()
        if let user = self.user {
            userProto.id = user.userId ?? ""
            userProto.longName = user.longName ?? ""
            userProto.shortName = user.shortName ?? ""
            userProto.hwModel = HardwareModel(rawValue: Int(user.hwModelId)) ?? .unset
            userProto.isLicensed = user.isLicensed
			if userProto.hasIsUnmessagable == true {
				userProto.isUnmessagable = user.unmessagable
			}
			userProto.role = Config.DeviceConfig.Role(rawValue: Int(user.role)) ?? .client
			userProto.publicKey = user.publicKey?.subdata(in: 0..<user.publicKey!.count) ?? Data()
        }
        var node = NodeInfo()
        node.num = UInt32(self.num)
        node.user = userProto
        // Add more fields as needed
        return node
    }
}
