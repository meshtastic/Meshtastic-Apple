//
//  AccessoryManager+Lockdown.swift
//  Meshtastic
//
//  The LockdownSender each radio's LockdownCoordinator sends through.
//  See specs/007-lockdown-mode/contracts/coordinator-protocol.md for the contract.
//
import Foundation
import OSLog
import MeshtasticProtobufs

/// Sends one radio's lock-down packets on its own connection: every connected radio has its own
/// `LockdownCoordinator` (feature 021, T301), which holds this weakly; its session keeps it.
///
/// CRITICAL field invariants. The firmware ToRadio gate is strict:
///   - to = myNodeNum
///   - from unset (proto default 0; firmware treats as "local PhoneAPI")
///   - channel = 0, wantAck = true
///   - hopLimit = hopStart = 7, priority = .reliable
///   - decoded.portnum = .adminApp
///   - decoded.payload = AdminMessage{lockdownAuth: ...}.serializedData()
///   - pkiEncrypted MUST NOT be set
@MainActor
final class SessionLockdownSender: LockdownSender {
	weak var session: RadioSession?

	/// The radio's node number, 0 until its MyInfo has arrived.
	var myNodeNum: UInt32 {
		guard let num = session?.nodeNum else { return 0 }
		return UInt32(truncatingIfNeeded: num)
	}

	func sendLockdownAuth(passphrase: Data,
						  bootsRemaining: UInt32,
						  validUntilEpoch: UInt32,
						  maxSessionSeconds: UInt32,
						  lockNow: Bool) {
		let myNum = self.myNodeNum
		guard let session, myNum != 0 else {
			Logger.mesh.warning("🔒 sendLockdownAuth: myNodeNum not yet known; dropping")
			return
		}
		var lockdownAuth = LockdownAuth()
		lockdownAuth.passphrase = passphrase
		lockdownAuth.bootsRemaining = bootsRemaining
		lockdownAuth.validUntilEpoch = validUntilEpoch
		lockdownAuth.maxSessionSeconds = maxSessionSeconds
		lockdownAuth.lockNow = lockNow
		guard let toRadio = AccessoryManager.lockdownAuthPacket(to: myNum, auth: lockdownAuth) else {
			Logger.mesh.error("🔒 sendLockdownAuth: failed to serialize AdminMessage")
			return
		}

		let name = session.device.longName ?? session.device.name
		let description = lockNow ? "🔒 Lockdown: Lock Now" : "🔒 Lockdown: passphrase submit"
		// The coordinator is fire-and-forget; a passphrase that can't be sent brings its sheet
		// back with the reason.
		Task { [weak session] in
			do {
				try await session?.connection.send(toRadio)
				Logger.mesh.info("📻 \(description, privacy: .public) to \(name, privacy: .public)")
			} catch {
				Logger.mesh.error("🔒 sendLockdownAuth to \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
				if !lockNow {
					session?.lockdown.passphraseSendFailed(String.localizedStringWithFormat("The passphrase couldn't be sent to %@. Check that it's still connected, then try again.".localized, name))
				}
			}
		}
	}
}

extension AccessoryManager {

	/// The `AdminMessage.lockdown_auth` packet for the radio `myNum`, with the field invariants
	/// in `SessionLockdownSender`. Shared by every radio (feature 021). Nil if the admin
	/// message can't be serialized.
	static func lockdownAuthPacket(to myNum: UInt32, auth lockdownAuth: LockdownAuth) -> ToRadio? {
		var adminMessage = AdminMessage()
		adminMessage.payloadVariant = .lockdownAuth(lockdownAuth)

		guard let adminData = try? adminMessage.serializedData() else { return nil }

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
		return toRadio
	}
}
