import Foundation

protocol DevicesDelegate {
	func onChange(devices: [Device])
	func onWantConfigFinished()
}
