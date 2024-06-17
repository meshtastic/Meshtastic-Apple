//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import CoreData
import MeshtasticProtobufs

extension NodeInfoEntity {
	var hasPositions: Bool {
		return positions?.count ?? 0 > 0
	}

	var hasDeviceMetrics: Bool {
		let deviceMetrics = telemetries?.filter { ($0 as AnyObject).metricsType == 0 }
		return deviceMetrics?.count ?? 0 > 0
	}

	var hasEnvironmentMetrics: Bool {
		let environmentMetrics = telemetries?.filter { ($0 as AnyObject).metricsType == 1 }
		return environmentMetrics?.count ?? 0 > 0
	}
	var hasDetectionSensorMetrics: Bool {
		return user?.sensorMessageList.count ?? 0 > 0
	}

	var hasTraceRoutes: Bool {
		return traceRoutes?.count ?? 0 > 0
	}

	var hasPax: Bool {
		return pax?.count ?? 0 > 0
	}

	var isStoreForwardRouter: Bool {
		return storeForwardConfig?.isRouter ?? false
	}

	var isOnline: Bool {
		let fifteenMinutesAgo = Calendar.current.date(byAdding: .minute, value: -15, to: Date())
		if lastHeard?.compare(fifteenMinutesAgo!) == .orderedDescending {
			 return true
		}
		return false
	}
	
	convenience init(
		context: NSManagedObjectContext,
		nodeInfo: NodeInfo
	) {
		self.init(context: context)
		self.id = Int64(nodeInfo.num)
		self.num = Int64(nodeInfo.num)
		self.channel = Int32(nodeInfo.channel)
		self.favorite = nodeInfo.isFavorite
		self.hopsAway = Int32(nodeInfo.hopsAway)
		self.viaMqtt = nodeInfo.viaMqtt
		
		if nodeInfo.hasDeviceMetrics {
			let newTelemetry = TelemetryEntity(context: context)
			newTelemetry.batteryLevel = Int32(nodeInfo.deviceMetrics.batteryLevel)
			newTelemetry.voltage = nodeInfo.deviceMetrics.voltage
			newTelemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
			newTelemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx
			
			var telemetries: [TelemetryEntity]
			if let tele = self.telemetries?.array as? [TelemetryEntity] {
				telemetries = tele
				telemetries.append(newTelemetry)
			} else {
				telemetries = [newTelemetry]
			}
			self.telemetries = NSOrderedSet(array: telemetries)
		}
		
		
		self.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
		self.snr = nodeInfo.snr
		
		// User
		var user: UserEntity?
		if nodeInfo.hasUser {
			user = UserEntity(
				context: context,
				user: nodeInfo.user,
				num: Int(nodeInfo.num)
			)
			self.user = user
		} else if nodeInfo.num > Int16.max {
			user = UserEntity(
				context: context,
				num: Int(nodeInfo.num)
			)
			self.user = user
		}
		if user == nil && self.num <= 0 {
			return
		}
			
		// Position
		if nodeInfo.isValidPosition {
			let position = PositionEntity(
				context: context,
				nodeInfo: nodeInfo
			)
			
			if let positions = positions?.mutableCopy() as? NSMutableOrderedSet {
				positions.add(position)
				self.positions = positions
			} else {
				self.positions = NSOrderedSet(object: position)
			}
		}
	}
	
	convenience init(
		context: NSManagedObjectContext,
		num: Int
	) {
		self.init(context: context)
		self.id = Int64(num)
		self.num = Int64(num)
		self.user = UserEntity(context: context, num: num)
	}
	
	func updated(
		context: NSManagedObjectContext,
		nodeInfo: NodeInfo
	) -> Self {
		self.id = Int64(nodeInfo.num)
		self.num = Int64(nodeInfo.num)
		self.channel = Int32(nodeInfo.channel)
		self.favorite = nodeInfo.isFavorite
		self.hopsAway = Int32(nodeInfo.hopsAway)
		self.viaMqtt = nodeInfo.viaMqtt
		
		if nodeInfo.hasDeviceMetrics {
			let newTelemetry = TelemetryEntity(context: context)
			newTelemetry.batteryLevel = Int32(nodeInfo.deviceMetrics.batteryLevel)
			newTelemetry.voltage = nodeInfo.deviceMetrics.voltage
			newTelemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
			newTelemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx
			
			var telemetries: [TelemetryEntity]
			if let tele = self.telemetries?.array as? [TelemetryEntity] {
				telemetries = tele
				telemetries.append(newTelemetry)
			} else {
				telemetries = [newTelemetry]
			}
			self.telemetries = NSOrderedSet(array: telemetries)
		}
		
		
		self.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
		self.snr = nodeInfo.snr
		
		// User
		var user: UserEntity?
		if nodeInfo.hasUser {
			user = UserEntity(
				context: context,
				user: nodeInfo.user,
				num: Int(nodeInfo.num)
			)
		} else if nodeInfo.num > Int16.max {
			user = UserEntity(
				context: context,
				num: Int(nodeInfo.num)
			)
		}
		self.user = user
		
		// Position
		if nodeInfo.isValidPosition {
			let position = PositionEntity(
				context: context,
				nodeInfo: nodeInfo
			)
			
			if let positions = positions?.mutableCopy() as? NSMutableOrderedSet {
				positions.add(position)
				self.positions = positions
			} else {
				self.positions = NSOrderedSet(object: position)
			}
		}
		
		return self
	}
}
