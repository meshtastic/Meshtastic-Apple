/// Helper abstraction for sharing functionality between channel and direct messaging.
enum MessageDestination {
	case user(UserEntity)
	case channel(ChannelEntity)

	var userNum: Int64 {
		switch self {
		case let .user(user): return user.num
		case .channel: return 0
		}
	}

	var channelNum: Int32 {
		switch self {
		case .user: return 0
		case let .channel(channel): return channel.index
		}
	}

	/// Whether the detection-sensor badge overlays messages sent to this destination. Detection
	/// Sensor telemetry only ever overlays channel broadcasts, never direct messages.
	var showsDetectionSensorBadge: Bool {
		switch self {
		case .user: return false
		case .channel: return true
		}
	}
}
