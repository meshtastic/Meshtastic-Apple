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
	nonisolated static func locationProviderSleepSeconds(configuredInterval: Int) -> Int {
		max(5, configuredInterval)
	}

	func initializeLocationProvider() {
		// One loop at a time: it's started again when another radio takes the focus.
		locationTask?.cancel()
		self.locationTask = Task {
			repeat {
				let sleepSeconds = Self.locationProviderSleepSeconds(configuredInterval: UserDefaults.provideLocationInterval)
				try? await Task.sleep(for: .seconds(sleepSeconds)) // Throws if task is cancelled

				// Every connected radio, the focused one first. With the focused radio gone and
				// others still connected (a handover pending), they keep getting it (T185).
				let radios = connectedRadioNums
				guard !radios.isEmpty else {
					return
				}
				let focusedNum = activeConnection?.device.num

				if UserDefaults.provideLocation {
					if let focusedNum {
						_ = try await sendPosition(channel: 0, destNum: focusedNum, wantResponse: false)
					}
					// Feature 021 (T101): every connected radio gets the phone's position, each on
					// its own connection. Their failures don't end the loop the focused radio drives.
					for radioNum in radios where radioNum != focusedNum {
						do {
							try await sendPosition(channel: 0, destNum: radioNum, wantResponse: false, viaRadio: radioNum)
						} catch {
							Logger.services.warning("📍 Could not share the phone's position with \(radioNum.toHex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
						}
					}
				}
			} while !Task.isCancelled
		}
	}

	/// Sends the phone's position. `viaRadio` picks the connected radio that sends it (feature
	/// 021); nil is the focused radio.
	public func sendPosition(channel: Int32, destNum: Int64, hopsAway: Int32 = 0, wantResponse: Bool, viaRadio: Int64? = nil) async throws {
		guard let session = connectedSession(forRadio: viaRadio), let fromNodeNum = session.nodeNum else {
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
		if hopsAway > 0 {
			meshPacket.hopLimit = UInt32(truncatingIfNeeded: hopsAway)
		}
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
		try await self.send(toRadio, via: session)
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
