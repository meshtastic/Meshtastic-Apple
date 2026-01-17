//
//  AccessoryManager+Position.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/24/25.
//

import Foundation
import OSLog
import MeshtasticProtobufs
import CoreLocation
import CoreData

extension AccessoryManager {
	func initializeLocationProvider() {
		self.locationTask = Task {
			repeat {
				try? await Task.sleep(for: .seconds(30)) // sleep for 30 seconds. This throws if task is cancelled

				guard let fromNodeNum = activeConnection?.device.num else {
					return
				}

				if UserDefaults.provideLocation {
					_ = try await sendPosition(channel: 0, destNum: fromNodeNum, wantResponse: false)
				}
			} while !Task.isCancelled
		}
	}

	public func sendPosition(channel: Int32, destNum: Int64, hopsAway: Int32 = 0, wantResponse: Bool,context: NSManagedObjectContext? = nil) async throws {
		guard let fromNodeNum = activeConnection?.device.num else {
			throw AccessoryError.ioFailed("Not connected to any device")
		}
		
		print("Sending with want response \(wantResponse)")

		guard let positionPacket = try await getPositionFromPhoneGPS(destNum: destNum, fixedPosition: false) else {
			Logger.services.error("Unable to get position data from device GPS to send to node")
			throw AccessoryError.appError("Unable to get position data from device GPS to send to node")
		}
		
		// Fetch the users involved in this position share
		let messageUsers = UserEntity.fetchRequest()
		messageUsers.predicate = NSPredicate(format: "num IN %@", [fromNodeNum, destNum])
		
		guard let context = context else {
			throw AccessoryError.ioFailed("No context available")
		}

		do {
			let fetchedUsers = try context.fetch(messageUsers)
			if fetchedUsers.isEmpty {
				throw AccessoryError.ioFailed("Message Users Not Found")
			}
			
			// Create a LocationEntity from the position data
			let locationEntity = LocationEntity(context: context)
			locationEntity.latitudeI = positionPacket.latitudeI
			locationEntity.longitudeI = positionPacket.longitudeI
			locationEntity.altitude = positionPacket.altitude
			locationEntity.speed = Int32(positionPacket.groundSpeed)
			locationEntity.heading = Int32(positionPacket.groundTrack)
			
			// Create the MessageEntity for the position share
			let newMessage = MessageEntity(context: context)
			newMessage.messageId = Int64(UInt32.random(in: UInt32(UInt8.max)..<UInt32.max))
			newMessage.messageTimestamp = Int32(Date().timeIntervalSince1970)
			newMessage.receivedACK = false
			newMessage.read = true
			
			if destNum > 0 {
				newMessage.toUser = fetchedUsers.first(where: { $0.num == destNum })
				newMessage.toUser?.lastMessage = Date()
//				if newMessage.toUser?.pkiEncrypted ?? false {
//					newMessage.publicKey = newMessage.toUser?.publicKey
//					newMessage.pkiEncrypted = true
//				}
			}
			
			newMessage.fromUser = fetchedUsers.first(where: { $0.num == fromNodeNum })
			newMessage.isEmoji = false
			newMessage.admin = false
			newMessage.channel = channel
			newMessage.messagePayload = "" // Empty for position messages
			newMessage.messagePayloadMarkdown = "" // Empty for position messages
			newMessage.positionExchange = locationEntity // Link the location
			newMessage.read = true

			// Prepare the mesh packet
			var meshPacket = MeshPacket()
			meshPacket.to = UInt32(destNum)
			meshPacket.channel = UInt32(channel)
			meshPacket.from = UInt32(fromNodeNum)
			meshPacket.id = UInt32(newMessage.messageId)
			
			if hopsAway > 0 {
				meshPacket.hopLimit = UInt32(truncatingIfNeeded: hopsAway)
			} else {
				let toUserHopsAway = newMessage.toUser?.userNode?.hopsAway ?? 0
				if toUserHopsAway > Int32(truncatingIfNeeded: newMessage.fromUser?.userNode?.loRaConfig?.hopLimit ?? 0) {
					meshPacket.hopLimit = UInt32(truncatingIfNeeded: toUserHopsAway)
				}
			}
//			
//			if newMessage.toUser?.pkiEncrypted ?? false {
//				meshPacket.pkiEncrypted = true
//				meshPacket.publicKey = newMessage.toUser?.publicKey ?? Data()
//			}
			
			var dataMessage = DataMessage()
			if let serializedData: Data = try? positionPacket.serializedData() {
				dataMessage.payload = serializedData
				dataMessage.portnum = PortNum.positionApp
				dataMessage.wantResponse = wantResponse
				meshPacket.decoded = dataMessage
			} else {
				Logger.services.error("Failed to serialize position packet data")
				throw AccessoryError.ioFailed("sendPosition: Unable to serialize position packet data")
			}
			
			
			
			meshPacket.wantAck = true

			var toRadio: ToRadio!
			toRadio = ToRadio()
			toRadio.packet = meshPacket
			
			Task {
				let logString = String.localizedStringWithFormat("Sent position message %@ from %@ to %@".localized, String(newMessage.messageId), fromNodeNum.toHex(), destNum.toHex())
				try await send(toRadio, debugDescription: logString)
			}
			
			do {
				try context.save()
				Logger.data.info("💾 Saved a new position message from \(fromNodeNum.toHex(), privacy: .public) to \(destNum.toHex(), privacy: .public)")
			} catch {
				context.rollback()
				let nsError = error as NSError
				Logger.data.error("Unresolved Core Data error in Send Position Function. Error: \(nsError, privacy: .public)")
				throw error
			}
			
		} catch {
			Logger.data.error("💥 Send position message failure from \(fromNodeNum.toHex(), privacy: .public) to \(destNum.toHex(), privacy: .public)")
			throw error
		}
	}

	public func getPositionFromPhoneGPS(destNum: Int64, fixedPosition: Bool) async throws -> Position? {
		var positionPacket = Position()

		guard let lastLocation = LocationsHandler.shared.locationsArray.last else {
			return nil
		}

		if lastLocation == CLLocation(latitude: 0, longitude: 0) {
			return nil
		}

		positionPacket.latitudeI = Int32(lastLocation.coordinate.latitude * 1e7)
		positionPacket.longitudeI = Int32(lastLocation.coordinate.longitude * 1e7)
		let timestamp = lastLocation.timestamp
		positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.altitude = Int32(lastLocation.altitude)
		positionPacket.satsInView = UInt32(LocationsHandler.satsInView)
		let currentSpeed = lastLocation.speed
		if currentSpeed > 0 && (!currentSpeed.isNaN || !currentSpeed.isInfinite) {
			positionPacket.groundSpeed = UInt32(currentSpeed)
		}
		let currentHeading = lastLocation.course
		if (currentHeading > 0  && currentHeading <= 360) && (!currentHeading.isNaN || !currentHeading.isInfinite) {
			positionPacket.groundTrack = UInt32(currentHeading)
		}
		/// Set location source for time
		if !fixedPosition {
			/// From GPS treat time as good
			positionPacket.locationSource = Position.LocSource.locExternal
		} else {
			/// From GPS, but time can be old and have drifted
			positionPacket.locationSource = Position.LocSource.locManual
		}
		return positionPacket
	}
}
