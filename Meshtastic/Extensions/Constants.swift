import Foundation

enum Constants {
	/// `UInt32.max` is used to identify messages that are being
	/// sent to a channel and are not a DM to an individual user. This is used
	/// in the `to` field of some mesh packets.
	static let emptyNodeNum = UInt32.max
	
	/// TODO: document me
	static let minimumNodeNum = Int16.max
}
