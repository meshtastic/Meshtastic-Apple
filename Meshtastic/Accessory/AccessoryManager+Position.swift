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

	public func sendPosition(channel: Int32, destNum: Int64, wantResponse: Bool) async throws {
		guard let fromNodeNum = activeConnection?.device.num else {
			throw AccessoryError.ioFailed("Not connected to any device")
		}

		guard let positionPacket = try await getPositionFromPhoneGPS(destNum: destNum, fixedPosition: false) else {
			Logger.services.error("Unable to get position data from device GPS to send to node")
			throw AccessoryError.appError("Unable to get position data from device GPS to send to node")
		}

		var meshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.channel = UInt32(channel)
		meshPacket.from	= UInt32(fromNodeNum)
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

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		try await self.send(toRadio)
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
