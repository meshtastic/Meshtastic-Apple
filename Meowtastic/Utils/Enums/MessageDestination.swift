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
}
