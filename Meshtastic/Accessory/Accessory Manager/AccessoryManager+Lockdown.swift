//
//  AccessoryManager+Lockdown.swift
//  Meshtastic
//
//  Conformance making AccessoryManager the LockdownSender for LockdownCoordinator.
//  See specs/007-lockdown-mode/contracts/coordinator-protocol.md for the contract.
//
import Foundation
import OSLog
import MeshtasticProtobufs

extension AccessoryManager: LockdownSender {

	/// myNodeNum required by LockdownCoordinator for `MeshPacket.to`.
	/// `activeConnection?.device.num` is the same value AccessoryManager
	/// already uses for routing and admin operations.
	var myNodeNum: UInt32 {
		guard let num = activeConnection?.device.num else { return 0 }
		return UInt32(num)
	}

	/// Build and send an AdminMessage.lockdown_auth ToRadio packet.
	/// CRITICAL field invariants. The firmware ToRadio gate is strict:
	///   - to = myNodeNum
	///   - from unset (proto default 0; firmware treats as "local PhoneAPI")
	///   - channel = 0, wantAck = true
	///   - hopLimit = hopStart = 7, priority = .reliable
	///   - decoded.portnum = .adminApp
	///   - decoded.payload = AdminMessage{lockdownAuth: ...}.serializedData()
	///   - pkiEncrypted MUST NOT be set
	func sendLockdownAuth(passphrase: Data,
						  bootsRemaining: UInt32,
						  validUntilEpoch: UInt32,
						  maxSessionSeconds: UInt32,
						  lockNow: Bool) {
		let myNum = self.myNodeNum
		guard myNum != 0 else {
			Logger.mesh.warning("🔒 sendLockdownAuth: myNodeNum not yet known; dropping")
			return
		}

		var lockdownAuth = LockdownAuth()
		lockdownAuth.passphrase = passphrase
		lockdownAuth.bootsRemaining = bootsRemaining
		lockdownAuth.validUntilEpoch = validUntilEpoch
		lockdownAuth.maxSessionSeconds = maxSessionSeconds
		lockdownAuth.lockNow = lockNow

		var adminMessage = AdminMessage()
		adminMessage.payloadVariant = .lockdownAuth(lockdownAuth)

		guard let adminData = try? adminMessage.serializedData() else {
			Logger.mesh.error("🔒 sendLockdownAuth: failed to serialize AdminMessage")
			return
		}

		var dataMessage = DataMessage()
		dataMessage.portnum = .adminApp
		dataMessage.payload = adminData

		var meshPacket = MeshPacket()
		meshPacket.to = myNum
		// meshPacket.from intentionally NOT set. Proto default 0 means firmware
		// treats this as local PhoneAPI.
		meshPacket.channel = 0
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.wantAck = true
		meshPacket.hopLimit = 7
		meshPacket.hopStart = 7
		meshPacket.priority = .reliable
		meshPacket.decoded = dataMessage
		// pkiEncrypted intentionally NOT set.

		var toRadio = ToRadio()
		toRadio.packet = meshPacket

		let description = lockNow ? "🔒 Lockdown: Lock Now" : "🔒 Lockdown: passphrase submit"
		// `send(...)` is async; the coordinator is fire-and-forget here so we hop
		// to a Task and report failures via Logger.
		Task {
			do {
				try await self.send(toRadio, debugDescription: description)
			} catch {
				Logger.mesh.error("🔒 sendLockdownAuth send failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
