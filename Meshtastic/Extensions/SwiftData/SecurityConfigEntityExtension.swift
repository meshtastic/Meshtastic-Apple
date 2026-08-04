import SwiftData
import MeshtasticProtobufs

extension SecurityConfigEntity {
	/// The persisted packet authenticity policy decoded back into its protobuf enum.
	///
	/// `init?(rawValue:)` maps values this app version does not know to `.UNRECOGNIZED` rather than
	/// `nil`, so a policy set by newer firmware survives a read/write round trip instead of being
	/// silently reset to Compatible.
	var storedPacketSignaturePolicy: Config.SecurityConfig.PacketSignaturePolicy {
		Config.SecurityConfig.PacketSignaturePolicy(rawValue: Int(packetSignaturePolicy)) ?? .compatible
	}
}
