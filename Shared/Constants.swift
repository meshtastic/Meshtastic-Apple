import Foundation
import SwiftUI
enum Constants {
	/// `UInt32.max` or FFFF,FFFF in hex is used to identify messages that are being
	/// sent to a channel and are not a DM to an individual user. This is used
	/// in the `to` field of some mesh packets.
	static let maximumNodeNum = UInt32.max
	/// Based on the NUM_RESERVED from the firmware.
	/// https://github.com/meshtastic/firmware/blob/46d7b82ac1a4292ba52ca690e1a433d3a501a9e5/src/mesh/NodeDB.cpp#L522
	static let minimumNodeNum = 4

	// String used to render a nil value.  If changed, mark the new entry in
	// Localizable.xcstrings as "do not translate" and remove the old key.
	static let nilValueIndicator = "--"
}
