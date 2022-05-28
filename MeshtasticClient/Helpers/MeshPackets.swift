//
//  MeshPackets.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/27/22.
//

import Foundation
import CoreData

func nodeInfoPacket (packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {

	let fetchNodeInfoAppRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoAppRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

	do {

		let fetchedNode = try context.fetch(fetchNodeInfoAppRequest) as! [NodeInfoEntity]

		if fetchedNode.count == 1 {
			fetchedNode[0].id = Int64(packet.from)
			fetchedNode[0].num = Int64(packet.from)
			fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
			fetchedNode[0].snr = packet.rxSnr

		} else {
			return
		}
		do {

			try context.save()

			if meshLogging { MeshLogger.log("💾 Updated NodeInfo SNR \(packet.rxSnr) and Time from Node Info App Packet For: \(fetchedNode[0].num)")}
			print("💾 Updated NodeInfo SNR \(packet.rxSnr) and Time from Packet For: \(fetchedNode[0].num)")

		} catch {

			context.rollback()

			let nsError = error as NSError
			print("💥 Error Saving NodeInfoEntity from NODEINFO_APP \(nsError)")

		}
	} catch {

		print("💥 Error Fetching NodeInfoEntity for NODEINFO_APP")
	}
}

func positionPacket (packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {
	
	let fetchNodePositionRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodePositionRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

	do {

		let fetchedNode = try context.fetch(fetchNodePositionRequest) as! [NodeInfoEntity]

		if fetchedNode.count == 1 {
			
			fetchedNode[0].id = Int64(packet.from)
			fetchedNode[0].num = Int64(packet.from)
			fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
			fetchedNode[0].snr = packet.rxSnr
				
			if let positionMessage = try? Position(serializedData: packet.decoded.payload) {
				
				let position = PositionEntity(context: context)
				position.latitudeI = positionMessage.latitudeI
				position.longitudeI = positionMessage.longitudeI
				position.altitude = positionMessage.altitude
				position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))

				let mutablePositions = fetchedNode[0].positions!.mutableCopy() as! NSMutableOrderedSet
				mutablePositions.add(position)
				
				fetchedNode[0].positions = mutablePositions.copy() as? NSOrderedSet
			}
			
		} else {
			
			return
		}
		do {

		  try context.save()

			if meshLogging {
				MeshLogger.log("💾 Updated NodeInfo Position Coordinates, SNR \(packet.rxSnr) and Time from Position App Packet For: \(fetchedNode[0].num)")
			}
			print("💾 Updated NodeInfo Position Coordinates, SNR \(packet.rxSnr) and Time from Position App Packet For: \(fetchedNode[0].num)")

		} catch {

			context.rollback()

			let nsError = error as NSError
			print("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError)")
		}
	} catch {

		print("💥 Error Fetching NodeInfoEntity for POSITION_APP")
	}

}

func routingPacket (packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {
	
	if let routingMessage = try? Routing(serializedData: packet.decoded.payload) {
							print(packet.decoded.requestID)
							print(routingMessage)
		
		let error = routingMessage.errorReason
		
		var errorExplanation = "Unknown Routing Error"
		
		switch error {
			case Routing.Error.none:
				errorExplanation = "This message is not a failure"
			case Routing.Error.noRoute:
				errorExplanation = "Our node doesn't have a route to the requested destination anymore."
			case Routing.Error.gotNak:
				errorExplanation = "We received a nak while trying to forward on your behalf"
			case Routing.Error.timeout:
				errorExplanation = "Timeout"
			case Routing.Error.noInterface:
				errorExplanation = "No suitable interface could be found for delivering this packet"
			case Routing.Error.maxRetransmit:
				errorExplanation = "We reached the max retransmission count (typically for naive flood routing)"
			case Routing.Error.noChannel:
				errorExplanation = "No suitable channel was found for sending this packet (i.e. was requested channel index disabled?)"
			case Routing.Error.tooLarge:
				errorExplanation = "The packet was too big for sending (exceeds interface MTU after encoding)"
			case Routing.Error.noResponse:
				errorExplanation = "The request had want_response set, the request reached the destination node, but no service on that node wants to send a response (possibly due to bad channel permissions)"
			case Routing.Error.badRequest:
				errorExplanation = "The application layer service on the remote node received your request, but considered your request somehow invalid"
			case Routing.Error.notAuthorized:
				errorExplanation = "The application layer service on the remote node received your request, but considered your request not authorized (i.e you did not send the request on the required bound channel)"
			fallthrough
			default:
			print(error)
		}
		
		if meshLogging { MeshLogger.log("🕸️ ROUTING PACKET received for RequestID: \(packet.decoded.requestID) Error: \(errorExplanation)") }
		print("🕸️ ROUTING PACKET received for RequestID: \(packet.decoded.requestID) Error: \(errorExplanation)")
						
		if routingMessage.errorReason == Routing.Error.none {
			
			print("Priority ACK no Error")
			
			let fetchMessageRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
			fetchMessageRequest.predicate = NSPredicate(format: "messageId == %lld", Int64(packet.decoded.requestID))

			do {

				let fetchedMessage = try context.fetch(fetchMessageRequest)[0] as? MessageEntity
				
				if fetchedMessage != nil {
					
					fetchedMessage!.receivedACK = true
					fetchedMessage!.ackSNR = packet.rxSnr
					fetchedMessage!.ackTimestamp = Int32(packet.rxTime)
					fetchedMessage!.objectWillChange.send()
				}
				
				try context.save()

				  if meshLogging {
					  MeshLogger.log("💾 ACK Received and saved for MessageID \(packet.decoded.requestID)")
				  }
				  print("💾 ACK Received and saved for MessageID \(packet.decoded.requestID)")
				
			} catch {
				
				context.rollback()

				let nsError = error as NSError
				print("💥 Error Saving ACK for message MessageID \(packet.id) Error: \(nsError)")
			}
		}
	}
}
	
func telemetryPacket(packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {
	
	if let telemetryMessage = try? Telemetry(serializedData: packet.decoded.payload) {
		
		let telemetry = TelemetryEntity(context: context)
		print(packet.decoded.requestID)
		
		if meshLogging { MeshLogger.log("ℹ️ MESH PACKET received for Telemetry App UNHANDLED \(telemetryMessage)") }
		print("ℹ️ MESH PACKET received for Telemetry App UNHANDLED \(telemetryMessage)")
		
	} else {
		
	}
}

func textMessageAppPacket(packet: MeshPacket, connectedNode: Int64, meshLogging: Bool, context: NSManagedObjectContext) {
	
	let broadcastNodeNum: UInt32 = 4294967295
		
	if let messageText = String(bytes: packet.decoded.payload, encoding: .utf8) {

		print("💬 BLE FROMRADIO received for text message app \(messageText)")
		if meshLogging { MeshLogger.log("💬 BLE FROMRADIO received for text message app \(messageText)") }

		let messageUsers: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
		messageUsers.predicate = NSPredicate(format: "num IN %@", [packet.to, packet.from])

		do {

			let fetchedUsers = try context.fetch(messageUsers) as! [UserEntity]

			let newMessage = MessageEntity(context: context)
			newMessage.messageId = Int64(packet.id)
			newMessage.messageTimestamp = Int32(bitPattern: packet.rxTime)
			newMessage.receivedACK = false
			newMessage.direction = "IN"
			newMessage.isEmoji = packet.decoded.emoji == 1
			
			if packet.decoded.replyID > 0 {
				
				newMessage.replyID = Int64(packet.decoded.replyID)
			}

			if packet.to == broadcastNodeNum && fetchedUsers.count == 1 {

				// Save the broadcast user if it does not exist
				let bcu: UserEntity = UserEntity(context: context)
				bcu.shortName = "ALL"
				bcu.longName = "All - Broadcast"
				bcu.hwModel = "UNSET"
				bcu.num = Int64(broadcastNodeNum)
				bcu.userId = "BROADCASTNODE"
				newMessage.toUser = bcu

			} else {

				newMessage.toUser = fetchedUsers.first(where: { $0.num == packet.to })
			}

			newMessage.fromUser = fetchedUsers.first(where: { $0.num == packet.from })
			newMessage.messagePayload = messageText

			do {

				try context.save()
				print("💾 Saved a new message for \(packet.id)")
				if meshLogging { MeshLogger.log("💾 Saved a new message for \(newMessage.messageId)") }
				
				if newMessage.toUser != nil && newMessage.toUser!.num == broadcastNodeNum || connectedNode == newMessage.toUser!.num {
					
					// Create an iOS Notification for the received message and schedule it immediately
					let manager = LocalNotificationManager()

					manager.notifications = [
						Notification(
							id: ("notification.id.\(newMessage.messageId)"),
							title: "\(newMessage.fromUser?.longName ?? "Unknown")",
							subtitle: "AKA \(newMessage.fromUser?.shortName ?? "???")",
							content: messageText)
					]
					manager.schedule()
					if meshLogging { MeshLogger.log("💬 iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "Unknown") \(messageText)") }

				}
				
			} catch {

				context.rollback()

					let nsError = error as NSError
					print("💥 Failed to save new MessageEntity \(nsError)")
				}

			} catch {

			print("💥 Fetch Message To and From Users Error")
		}
	}
}
