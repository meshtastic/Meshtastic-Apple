import Foundation

// Temporary (i fucking wish!) wrapper to separate whole observable BLEManager from one-direction actions (commands)
final class BLEActions: ObservableObject {
	private let bleManager: BLEManager

	init(bleManager: BLEManager) {
		self.bleManager = bleManager
	}

	@discardableResult
	func sendMessage(
		message: String,
		toUserNum: Int64,
		channel: Int32,
		isEmoji: Bool,
		replyID: Int64
	) -> Bool {
		bleManager.sendMessage(
			message: message,
			toUserNum: toUserNum,
			channel: channel,
			isEmoji: isEmoji,
			replyID: replyID
		)
	}

	@discardableResult
	func sendPosition(
		channel: Int32,
		destNum: Int64,
		wantResponse: Bool
	) -> Bool {
		bleManager.sendPosition(
			channel: channel,
			destNum: destNum,
			wantResponse: wantResponse
		)
	}

	@discardableResult
	func sendTraceRouteRequest(
		destNum: Int64,
		wantResponse: Bool
	) -> Bool {
		bleManager.sendTraceRouteRequest(
			destNum: destNum,
			wantResponse: wantResponse
		)
	}
}
