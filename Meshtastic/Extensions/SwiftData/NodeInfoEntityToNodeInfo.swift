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

extension UserEntity {
	func toProto() -> User {
		var userProto = User()
			userProto.id = self.userId ?? ""
			userProto.longName = self.longName ?? ""
			userProto.shortName = self.shortName ?? ""
			userProto.hwModel = HardwareModel(rawValue: Int(self.hwModelId)) ?? .unset
			userProto.isLicensed = self.isLicensed
			if userProto.hasIsUnmessagable == true {
				userProto.isUnmessagable = self.unmessagable
			}
			userProto.role = Config.DeviceConfig.Role(rawValue: Int(self.role)) ?? .client
			userProto.publicKey = self.publicKey?.subdata(in: 0..<self.publicKey!.count) ?? Data()
		return userProto
	}
}
