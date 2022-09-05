//
//  MeshPackets.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/27/22.
//

import Foundation
import CoreData
import SwiftUI

func localConfig (config: Config, meshlogging: Bool, context:NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {
	
	// We don't care about any of the Power settings
	// We don't want to manage wifi from the phone app and disconnect our device
	if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
		
		var isDefault = false
		
		if (try! config.device.jsonString()) == "{}" {
			
			isDefault = true
			print("📟 Default Device config")
			
		} else {
			
			print("📟 Custom Device config")
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].deviceConfig == nil {
					
					let newDeviceConfig = DeviceConfigEntity(context: context)
					
					if isDefault {

						// Client default protobuf value of 0
						newDeviceConfig.role = 0
						newDeviceConfig.serialEnabled = true
						newDeviceConfig.debugLogEnabled = false
						
					} else {

						// Client default protobuf value of 0
						newDeviceConfig.role = Int32(config.device.role.rawValue)
						newDeviceConfig.serialEnabled = !config.device.serialDisabled
						newDeviceConfig.debugLogEnabled = config.device.debugLogEnabled
					}
					fetchedNode[0].deviceConfig = newDeviceConfig
					
				} else {
					
					if isDefault {
						
						// Client default protobuf value of 0
						fetchedNode[0].deviceConfig?.role = 0
						fetchedNode[0].deviceConfig?.serialEnabled = true
						fetchedNode[0].deviceConfig?.debugLogEnabled = false
						
					} else {
						// Client default protobuf value of 0
						fetchedNode[0].deviceConfig?.role = Int32(config.device.role.rawValue)
						fetchedNode[0].deviceConfig?.serialEnabled = !config.device.serialDisabled
						fetchedNode[0].deviceConfig?.debugLogEnabled = config.device.debugLogEnabled
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Device Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data DeviceConfigEntity: \(nsError)")
				}
			}
			
		} catch {
			
		}
	}
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.bluetooth(config.bluetooth) {
		
		var isDefault = false
		
		if (try! config.bluetooth.jsonString()) == "{}" {
			
			isDefault = true
			print("📶 Default Bluetooth config")
			if meshlogging { MeshLogger.log("🖥️ Default Bluetooth config \(String(nodeNum))") }
			
		} else {
			
			if meshlogging { MeshLogger.log("🖥️ Custom Bluetooth config \(String(nodeNum))") }
			print("📶 Custom Bluetooth config")
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].bluetoothConfig == nil {
					
					let newBluetoothConfig = BluetoothConfigEntity(context: context)
					
					if isDefault {

						newBluetoothConfig.enabled = true
						newBluetoothConfig.mode = Int32(config.bluetooth.mode.rawValue)
						newBluetoothConfig.fixedPin = Int32("123456") ?? 123456
						
					} else {

						newBluetoothConfig.enabled = config.bluetooth.enabled
						newBluetoothConfig.mode = Int32(config.bluetooth.mode.rawValue)
						newBluetoothConfig.fixedPin = Int32(config.bluetooth.fixedPin)

					}
					fetchedNode[0].bluetoothConfig = newBluetoothConfig
					
				} else {
					
					if isDefault {
						
						fetchedNode[0].bluetoothConfig?.enabled = true
						fetchedNode[0].bluetoothConfig?.mode = Int32(config.bluetooth.mode.rawValue)
						fetchedNode[0].bluetoothConfig?.fixedPin = Int32("123456") ?? 123456
						
					} else {

						fetchedNode[0].bluetoothConfig?.enabled = config.bluetooth.enabled
						fetchedNode[0].bluetoothConfig?.mode = Int32(config.bluetooth.mode.rawValue)
						fetchedNode[0].bluetoothConfig?.fixedPin = Int32(config.bluetooth.fixedPin)

					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Bluetooth Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data BluetoothConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Bluetooth Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data BluetoothConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.display(config.display) {
		
		var isDefault = false
		
		if (try! config.display.jsonString()) == "{}" {
			
			isDefault = true
			
			if meshlogging { MeshLogger.log("🖥️ Default Display config \(String(nodeNum))") }
			
		} else {
			
			if meshlogging { MeshLogger.log("🖥️ Custom Display config \(String(nodeNum))") }
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].displayConfig == nil {
					
					let newDisplayConfig = DisplayConfigEntity(context: context)
					
					if isDefault {

						newDisplayConfig.screenOnSeconds = 0
						newDisplayConfig.screenCarouselInterval = 0
						newDisplayConfig.gpsFormat = 0
						newDisplayConfig.compassNorthTop = false
						
					} else {

						newDisplayConfig.gpsFormat = Int32(config.display.gpsFormat.rawValue)
						newDisplayConfig.screenOnSeconds = Int32(config.display.screenOnSecs)
						newDisplayConfig.screenCarouselInterval = Int32(config.display.autoScreenCarouselSecs)
						newDisplayConfig.compassNorthTop = config.display.compassNorthTop
					}
					fetchedNode[0].displayConfig = newDisplayConfig
					
				} else {
					
					if isDefault {
						
						fetchedNode[0].displayConfig?.screenOnSeconds = 0
						fetchedNode[0].displayConfig?.screenCarouselInterval = 0
						fetchedNode[0].displayConfig?.gpsFormat = 0
						fetchedNode[0].displayConfig?.compassNorthTop = false
						
					} else {

						fetchedNode[0].displayConfig?.gpsFormat = Int32(config.display.gpsFormat.rawValue)
						fetchedNode[0].displayConfig?.screenOnSeconds = Int32(config.display.screenOnSecs)
						fetchedNode[0].displayConfig?.screenCarouselInterval = Int32(config.display.autoScreenCarouselSecs)
						fetchedNode[0].displayConfig?.compassNorthTop = config.display.compassNorthTop
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Display Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data DisplayConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Display Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data DisplayConfigEntity failed: \(nsError)")
		}
	}
		
	if config.payloadVariant == Config.OneOf_PayloadVariant.lora(config.lora) {
		
		var isDefault = false
		
		if (try! config.lora.jsonString()) == "{}" {
			
			isDefault = true
			if meshlogging { MeshLogger.log("📻 Default LoRa config \(String(nodeNum))") }
			
		} else {
			
			if meshlogging { MeshLogger.log("📻 Custom LoRa config \(String(nodeNum))") }
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save LoRa Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].loRaConfig == nil {
					
					let newLoRaConfig = LoRaConfigEntity(context: context)
					
					if isDefault {
						
						// UNSET default protobuf value of 0
						newLoRaConfig.regionCode = 0
						// LongFast default protobuf value of 0
						newLoRaConfig.modemPreset = 0
						// 3 Hops default protobuf value of 0
						newLoRaConfig.hopLimit = 0
						// Default value of 0 is 22dbm
						newLoRaConfig.txPower = 0
						
					} else {
						
						newLoRaConfig.regionCode = Int32(config.lora.region.rawValue)
						newLoRaConfig.modemPreset = Int32(config.lora.modemPreset.rawValue)
						newLoRaConfig.hopLimit = Int32(config.lora.hopLimit)
						newLoRaConfig.txPower = Int32(config.lora.txPower)
						
					}
					
					fetchedNode[0].loRaConfig = newLoRaConfig
					
				} else {
					
					if isDefault {
						
						// UNSET default protobuf value of 0
						fetchedNode[0].loRaConfig?.regionCode = 0
						// LongFast default protobuf value of 0
						fetchedNode[0].loRaConfig?.modemPreset = 0
						// 3 Hops default protobuf value of 0
						fetchedNode[0].loRaConfig?.hopLimit = 0
						// Default value of 0 is 22dbm
						fetchedNode[0].loRaConfig?.txPower = 0
						
					} else {

						fetchedNode[0].loRaConfig?.regionCode = Int32(config.lora.region.rawValue)
						fetchedNode[0].loRaConfig?.modemPreset = Int32(config.lora.modemPreset.rawValue)
						fetchedNode[0].loRaConfig?.hopLimit = Int32(config.lora.hopLimit)
						fetchedNode[0].loRaConfig?.txPower = Int32(config.lora.txPower)
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated LoRa Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data LoRaConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Lora Config")
			}
			
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data LoRaConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.position(config.position) {
		
		var isDefault = false
		
		if (try! config.position.jsonString()) == "{}" {
			
			isDefault = true
			if meshlogging { MeshLogger.log("🗺️ Default Position config received \(String(nodeNum))") }
			
		} else {
			
			if meshlogging { MeshLogger.log("🗺️ Custom Position config received \(String(nodeNum))") }
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save LoRa Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].positionConfig == nil {
					
					let newPositionConfig = PositionConfigEntity(context: context)
					
					if isDefault {
						
						newPositionConfig.smartPositionEnabled = true
						newPositionConfig.deviceGpsEnabled = true
						newPositionConfig.fixedPosition = false
						newPositionConfig.gpsUpdateInterval = 0
						newPositionConfig.gpsAttemptTime = 0
						newPositionConfig.positionBroadcastSeconds = 0
						newPositionConfig.positionFlags = 3

					} else {
						
						newPositionConfig.smartPositionEnabled = !config.position.positionBroadcastSmartDisabled
						newPositionConfig.deviceGpsEnabled = !config.position.gpsDisabled
						newPositionConfig.fixedPosition = config.position.fixedPosition
						newPositionConfig.gpsUpdateInterval = Int32(config.position.gpsUpdateInterval)
						newPositionConfig.gpsAttemptTime = Int32(config.position.gpsAttemptTime)
						newPositionConfig.positionBroadcastSeconds = Int32(config.position.positionBroadcastSecs)
						newPositionConfig.positionFlags = Int32(config.position.positionFlags)
					}
					
					fetchedNode[0].positionConfig = newPositionConfig
					
				} else {
					
					if isDefault {
						
						fetchedNode[0].positionConfig?.smartPositionEnabled = true
						fetchedNode[0].positionConfig?.deviceGpsEnabled = true
						fetchedNode[0].positionConfig?.fixedPosition = false
						fetchedNode[0].positionConfig?.gpsUpdateInterval = 0
						fetchedNode[0].positionConfig?.gpsAttemptTime = 0
						fetchedNode[0].positionConfig?.positionBroadcastSeconds = 0
						fetchedNode[0].positionConfig?.positionFlags = 3
						
					} else {
						
						fetchedNode[0].positionConfig?.smartPositionEnabled = !config.position.positionBroadcastSmartDisabled
						fetchedNode[0].positionConfig?.deviceGpsEnabled = !config.position.gpsDisabled
						fetchedNode[0].positionConfig?.fixedPosition = config.position.fixedPosition
						fetchedNode[0].positionConfig?.gpsUpdateInterval = Int32(config.position.gpsUpdateInterval)
						fetchedNode[0].positionConfig?.gpsAttemptTime = Int32(config.position.gpsAttemptTime)
						fetchedNode[0].positionConfig?.positionBroadcastSeconds = Int32(config.position.positionBroadcastSecs)
						fetchedNode[0].positionConfig?.positionFlags = Int32(config.position.positionFlags)
				
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Position Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data PositionConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Position Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data PositionConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.wifi(config.wifi) {
		
		var isDefault = false
		
		if (try! config.wifi.jsonString()) == "{}" {
			
			isDefault = true
			if meshlogging { MeshLogger.log("📶 Default WiFi config received \(String(nodeNum))") }
			
		} else {
			
			if meshlogging { MeshLogger.log("📶 Custom WiFi config received \(String(nodeNum))") }
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save WiFi Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].wiFiConfig == nil {
					
					let newWiFiConfig = WiFiConfigEntity(context: context)
					
					if isDefault {
						
						newWiFiConfig.ssid = ""
						newWiFiConfig.password = ""
						newWiFiConfig.mode = 0

					} else {
						
						newWiFiConfig.ssid = config.wifi.ssid
						newWiFiConfig.password = config.wifi.psk
						newWiFiConfig.mode = Int32(config.wifi.mode.rawValue)
					}
					fetchedNode[0].wiFiConfig = newWiFiConfig
					
				} else {
					
					if isDefault {
						
						fetchedNode[0].wiFiConfig?.ssid = ""
						fetchedNode[0].wiFiConfig?.password = ""
						fetchedNode[0].wiFiConfig?.mode = 0
						
					} else {
						
						fetchedNode[0].wiFiConfig?.ssid = config.wifi.ssid
						fetchedNode[0].wiFiConfig?.password = config.wifi.psk
						fetchedNode[0].wiFiConfig?.mode = Int32(config.wifi.mode.rawValue)
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated WiFi Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data WiFiConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save WiFi Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data WiFiConfigEntity failed: \(nsError)")
		}
	}
}

func moduleConfig (config: ModuleConfig, meshlogging: Bool, context:NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {
	
	// We don't care about any of the WiFi related MQTT settings
	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(config.cannedMessage) {
		
		var isDefault = false
		
		if (try! config.cannedMessage.jsonString()) == "{}" {
			
			isDefault = true
			print("🥫 Default Canned Message Module config")
		} else {
			
			print("🥫 Custom Canned Message Module config")
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Canned Message Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].cannedMessageConfig == nil {
					
					let newCannedMessageConfig = CannedMessageConfigEntity(context: context)

					if isDefault {

						newCannedMessageConfig.enabled = false
						newCannedMessageConfig.sendBell = false
						newCannedMessageConfig.rotary1Enabled = false
						newCannedMessageConfig.updown1Enabled = false
						newCannedMessageConfig.inputbrokerPinA = 0
						newCannedMessageConfig.inputbrokerPinB = 0
						newCannedMessageConfig.inputbrokerPinPress = 0
						newCannedMessageConfig.inputbrokerEventCw = 0
						newCannedMessageConfig.inputbrokerEventCcw = 0
						newCannedMessageConfig.inputbrokerEventPress = 0

					} else {

						newCannedMessageConfig.enabled = config.cannedMessage.enabled
						newCannedMessageConfig.sendBell = config.cannedMessage.sendBell
						newCannedMessageConfig.rotary1Enabled = config.cannedMessage.rotary1Enabled
						newCannedMessageConfig.updown1Enabled = config.cannedMessage.updown1Enabled
						newCannedMessageConfig.inputbrokerPinA = Int32(config.cannedMessage.inputbrokerPinA)
						newCannedMessageConfig.inputbrokerPinB = Int32(config.cannedMessage.inputbrokerPinB)
						newCannedMessageConfig.inputbrokerPinPress = Int32(config.cannedMessage.inputbrokerPinPress)
						newCannedMessageConfig.inputbrokerEventCw = Int32(config.cannedMessage.inputbrokerEventCw.rawValue)
						newCannedMessageConfig.inputbrokerEventCcw = Int32(config.cannedMessage.inputbrokerEventCcw.rawValue)
						newCannedMessageConfig.inputbrokerEventPress = Int32(config.cannedMessage.inputbrokerEventPress.rawValue)
					}
					fetchedNode[0].cannedMessageConfig = newCannedMessageConfig
					
				} else {
					
					if isDefault {
												
						fetchedNode[0].cannedMessageConfig?.enabled = false
						fetchedNode[0].cannedMessageConfig?.sendBell = false
						fetchedNode[0].cannedMessageConfig?.rotary1Enabled = false
						fetchedNode[0].cannedMessageConfig?.updown1Enabled = false
						fetchedNode[0].cannedMessageConfig?.inputbrokerPinA = 0
						fetchedNode[0].cannedMessageConfig?.inputbrokerPinB = 0
						fetchedNode[0].cannedMessageConfig?.inputbrokerPinPress = 0
						fetchedNode[0].cannedMessageConfig?.inputbrokerEventCw = 0
						fetchedNode[0].cannedMessageConfig?.inputbrokerEventCcw = 0
						fetchedNode[0].cannedMessageConfig?.inputbrokerEventPress = 0
						
					} else {

						fetchedNode[0].cannedMessageConfig?.enabled = config.cannedMessage.enabled
						fetchedNode[0].cannedMessageConfig?.sendBell = config.cannedMessage.sendBell
						fetchedNode[0].cannedMessageConfig?.rotary1Enabled = config.cannedMessage.rotary1Enabled
						fetchedNode[0].cannedMessageConfig?.updown1Enabled = config.cannedMessage.updown1Enabled
						fetchedNode[0].cannedMessageConfig?.inputbrokerPinA = Int32(config.cannedMessage.inputbrokerPinA)
						fetchedNode[0].cannedMessageConfig?.inputbrokerPinB = Int32(config.cannedMessage.inputbrokerPinB)
						fetchedNode[0].cannedMessageConfig?.inputbrokerPinPress = Int32(config.cannedMessage.inputbrokerPinPress)
						fetchedNode[0].cannedMessageConfig?.inputbrokerEventCw = Int32(config.cannedMessage.inputbrokerEventCw.rawValue)
						fetchedNode[0].cannedMessageConfig?.inputbrokerEventCcw = Int32(config.cannedMessage.inputbrokerEventCcw.rawValue)
						fetchedNode[0].cannedMessageConfig?.inputbrokerEventPress = Int32(config.cannedMessage.inputbrokerEventPress.rawValue)
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Canned Message Module Config for node number: \(String(nodeNum))") }
					

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data CannedMessageConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Canned Message Module Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data CannedMessageConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.externalNotification(config.externalNotification) {
		
		var isDefault = false
		
		if (try! config.externalNotification.jsonString()) == "{}" {
			
			isDefault = true
			print("🚨 Default External Notifiation Module config")
			
		} else {
			
			print("🚨 Custom External Notifiation Module config")
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save External Notificaitone Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].externalNotificationConfig == nil {
					
					let newExternalNotificationConfig = ExternalNotificationConfigEntity(context: context)

					if isDefault {


						newExternalNotificationConfig.enabled = false
						newExternalNotificationConfig.alertBell = false
						newExternalNotificationConfig.alertMessage = false
						newExternalNotificationConfig.active = false
						newExternalNotificationConfig.output = 0
						newExternalNotificationConfig.outputMilliseconds = 0


					} else {

						newExternalNotificationConfig.enabled = config.externalNotification.enabled
						newExternalNotificationConfig.alertBell = config.externalNotification.alertBell
						newExternalNotificationConfig.alertMessage = config.externalNotification.alertMessage
						newExternalNotificationConfig.active = config.externalNotification.active
						newExternalNotificationConfig.output = Int32(config.externalNotification.output)
						newExternalNotificationConfig.outputMilliseconds = Int32(config.externalNotification.outputMs)
					}
					fetchedNode[0].externalNotificationConfig = newExternalNotificationConfig
					
				} else {
					
					if isDefault {
						
						fetchedNode[0].externalNotificationConfig?.enabled = false
						fetchedNode[0].externalNotificationConfig?.alertBell = false
						fetchedNode[0].externalNotificationConfig?.alertMessage = false
						fetchedNode[0].externalNotificationConfig?.active = false
						fetchedNode[0].externalNotificationConfig?.output = 0
						fetchedNode[0].externalNotificationConfig?.outputMilliseconds = 0
						
					} else {

						fetchedNode[0].externalNotificationConfig?.enabled = config.externalNotification.enabled
						fetchedNode[0].externalNotificationConfig?.alertBell = config.externalNotification.alertBell
						fetchedNode[0].externalNotificationConfig?.alertMessage = config.externalNotification.alertMessage
						fetchedNode[0].externalNotificationConfig?.active = config.externalNotification.active
						fetchedNode[0].externalNotificationConfig?.output = Int32(config.externalNotification.output)
						fetchedNode[0].externalNotificationConfig?.outputMilliseconds = Int32(config.externalNotification.outputMs)
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated External Notification Module Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data ExternalNotificationConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save External Notifiation Module Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data ExternalNotificationConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.rangeTest(config.rangeTest) {
		
		var isDefault = false
		
		if (try! config.rangeTest.jsonString()) == "{}" {
			
			isDefault = true
			print("⛰️ Default Range Test Module config")
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].rangeTestConfig == nil {
					
					let newRangeTestConfig = RangeTestConfigEntity(context: context)
					
					if isDefault {

						newRangeTestConfig.sender = 0
						newRangeTestConfig.enabled = false
						newRangeTestConfig.save = false
						
					} else {

						newRangeTestConfig.sender = Int32(config.rangeTest.sender)
						newRangeTestConfig.enabled = config.rangeTest.enabled
						newRangeTestConfig.save = config.rangeTest.save
					}
					fetchedNode[0].rangeTestConfig = newRangeTestConfig
					
				} else {
					
					if isDefault {
						
						fetchedNode[0].rangeTestConfig?.sender = 0
						fetchedNode[0].rangeTestConfig?.enabled = false
						fetchedNode[0].rangeTestConfig?.save = false
						
					} else {

						fetchedNode[0].rangeTestConfig?.sender = Int32(config.rangeTest.sender)
						fetchedNode[0].rangeTestConfig?.enabled = config.rangeTest.enabled
						fetchedNode[0].rangeTestConfig?.save = config.rangeTest.save
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Range Test Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data RangeTestConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Range Test Module Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data RangeTestConfigEntity failed: \(nsError)")
		}
	}

	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.serial(config.serial) {
		
		var isDefault = false
		
		if (try! config.serial.jsonString()) == "{}" {
			
			isDefault = true
			
			if meshlogging { MeshLogger.log("🤖 Default Serial Module config \(String(nodeNum))") }
			
		} else {
			
			if meshlogging { MeshLogger.log("🤖 Custom Serial Module config \(String(nodeNum))") }
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].serialConfig == nil {
					
					let newSerialConfig = SerialConfigEntity(context: context)
					
					if isDefault {

						newSerialConfig.enabled = false
						newSerialConfig.echo = false
						newSerialConfig.rxd = 0
						newSerialConfig.txd = 0
						newSerialConfig.baudRate = 0
						newSerialConfig.timeout = 0
						newSerialConfig.mode = 0
						
					} else {
				
						newSerialConfig.enabled = config.serial.enabled
						newSerialConfig.echo = config.serial.echo
						newSerialConfig.rxd = Int32(config.serial.rxd)
						newSerialConfig.txd = Int32(config.serial.txd)
						newSerialConfig.baudRate = Int32(config.serial.baud.rawValue)
						newSerialConfig.timeout = Int32(config.serial.timeout)
						newSerialConfig.mode = Int32(config.serial.mode.rawValue)
					}
					
					fetchedNode[0].serialConfig = newSerialConfig
					
				} else {
					
					if isDefault {
												
						fetchedNode[0].serialConfig?.enabled = false
						fetchedNode[0].serialConfig?.echo = false
						fetchedNode[0].serialConfig?.rxd = 0
						fetchedNode[0].serialConfig?.txd = 0
						fetchedNode[0].serialConfig?.baudRate = 0
						fetchedNode[0].serialConfig?.timeout = 0
						fetchedNode[0].serialConfig?.mode = 0
						
					} else {

						fetchedNode[0].serialConfig?.enabled = config.serial.enabled
						fetchedNode[0].serialConfig?.echo = config.serial.echo
						fetchedNode[0].serialConfig?.rxd = Int32(config.serial.rxd)
						fetchedNode[0].serialConfig?.txd = Int32(config.serial.txd)
						fetchedNode[0].serialConfig?.baudRate = Int32(config.serial.baud.rawValue)
						fetchedNode[0].serialConfig?.timeout = Int32(config.serial.timeout)
						fetchedNode[0].serialConfig?.mode = Int32(config.serial.mode.rawValue)
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Serial Module Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data SerialConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Serial Module Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data SerialConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.telemetry(config.telemetry) {
		
		var isDefault = false
		
		if (try! config.telemetry.jsonString()) == "{}" {
			
			isDefault = true
			print("📈 Default Telemetry Module config")
		}
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {

			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Telemetry Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].telemetryConfig == nil {
					
					let newTelemetryConfig = TelemetryConfigEntity(context: context)
					
					if isDefault {
						
						newTelemetryConfig.deviceUpdateInterval = 0
						newTelemetryConfig.environmentUpdateInterval = 0
						newTelemetryConfig.environmentMeasurementEnabled = false
						newTelemetryConfig.environmentScreenEnabled = false
						newTelemetryConfig.environmentDisplayFahrenheit = false
						
					} else {
						
						newTelemetryConfig.deviceUpdateInterval = Int32(config.telemetry.deviceUpdateInterval)
						newTelemetryConfig.environmentUpdateInterval = Int32(config.telemetry.environmentUpdateInterval)
						newTelemetryConfig.environmentMeasurementEnabled = config.telemetry.environmentMeasurementEnabled
						newTelemetryConfig.environmentScreenEnabled = config.telemetry.environmentScreenEnabled
						newTelemetryConfig.environmentDisplayFahrenheit = config.telemetry.environmentDisplayFahrenheit
					}
					fetchedNode[0].telemetryConfig = newTelemetryConfig
					
				} else {
					
					if isDefault {
						
						fetchedNode[0].telemetryConfig?.deviceUpdateInterval = 0
						fetchedNode[0].telemetryConfig?.environmentUpdateInterval = 0
						fetchedNode[0].telemetryConfig?.environmentMeasurementEnabled = false
						fetchedNode[0].telemetryConfig?.environmentScreenEnabled = false
						fetchedNode[0].telemetryConfig?.environmentDisplayFahrenheit = false
						
					} else {
						
						fetchedNode[0].telemetryConfig?.deviceUpdateInterval = Int32(config.telemetry.deviceUpdateInterval)
						fetchedNode[0].telemetryConfig?.environmentUpdateInterval = Int32(config.telemetry.environmentUpdateInterval)
						fetchedNode[0].telemetryConfig?.environmentMeasurementEnabled = config.telemetry.environmentMeasurementEnabled
						fetchedNode[0].telemetryConfig?.environmentScreenEnabled = config.telemetry.environmentScreenEnabled
						fetchedNode[0].telemetryConfig?.environmentDisplayFahrenheit = config.telemetry.environmentDisplayFahrenheit
					}
				}
				
				do {

					try context.save()
					if meshlogging { MeshLogger.log("💾 Updated Telemetry Module Config for node number: \(String(nodeNum))") }

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Updating Core Data TelemetryConfigEntity: \(nsError)")
				}
			} else {
				
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Telemetry Module Config")
			}
			
		} catch {
			
			let nsError = error as NSError
			print("💥 Fetching node for core data TelemetryConfigEntity failed: \(nsError)")
		}
	}
}

func myInfoPacket (myInfo: MyNodeInfo, meshLogging: Bool, context: NSManagedObjectContext) -> MyInfoEntity? {
	
	let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
	fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(myInfo.myNodeNum))

	do {
		let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
		// Not Found Insert
		if fetchedMyInfo.isEmpty {
			
			let myInfoEntity = MyInfoEntity(context: context)
			myInfoEntity.myNodeNum = Int64(myInfo.myNodeNum)
			myInfoEntity.hasGps = myInfo.hasGps_p
			myInfoEntity.hasWifi = myInfo.hasWifi_p
			myInfoEntity.bitrate = myInfo.bitrate

			// Swift does strings weird, this does work to get the version without the github hash
			let lastDotIndex = myInfo.firmwareVersion.lastIndex(of: ".")
			var version = myInfo.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: myInfo.firmwareVersion))]
			version = version.dropLast()
			myInfoEntity.firmwareVersion = String(version)
			myInfoEntity.messageTimeoutMsec = Int32(bitPattern: myInfo.messageTimeoutMsec)
			myInfoEntity.minAppVersion = Int32(bitPattern: myInfo.minAppVersion)
			myInfoEntity.maxChannels = Int32(bitPattern: myInfo.maxChannels)
			
			do {

				try context.save()
				if meshLogging { MeshLogger.log("💾 Saved a new myInfo for node number: \(String(myInfo.myNodeNum))") }
				return myInfoEntity

			} catch {

				context.rollback()

				let nsError = error as NSError
				print("💥 Error Inserting New Core Data MyInfoEntity: \(nsError)")
			}
			
		} else {

			fetchedMyInfo[0].myNodeNum = Int64(myInfo.myNodeNum)
			fetchedMyInfo[0].hasGps = myInfo.hasGps_p
			fetchedMyInfo[0].bitrate = myInfo.bitrate
			
			let lastDotIndex = myInfo.firmwareVersion.lastIndex(of: ".")//.lastIndex(of: ".", offsetBy: -1)
			var version = myInfo.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset:6, in: myInfo.firmwareVersion))]
			version = version.dropLast()
			fetchedMyInfo[0].firmwareVersion = String(version)
			fetchedMyInfo[0].messageTimeoutMsec = Int32(bitPattern: myInfo.messageTimeoutMsec)
			fetchedMyInfo[0].minAppVersion = Int32(bitPattern: myInfo.minAppVersion)
			fetchedMyInfo[0].maxChannels = Int32(bitPattern: myInfo.maxChannels)
			
			do {

				try context.save()
				if meshLogging { MeshLogger.log("💾 Updated myInfo for node number: \(String(myInfo.myNodeNum))") }
				return fetchedMyInfo[0]

			} catch {

				context.rollback()

				let nsError = error as NSError
				print("💥 Error Updating Core Data MyInfoEntity: \(nsError)")
			}
		}

	} catch {

		print("💥 Fetch MyInfo Error")
	}
	return nil
}

func nodeInfoPacket (nodeInfo: NodeInfo, meshLogging: Bool, context: NSManagedObjectContext) -> NodeInfoEntity? {
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeInfo.num))

	do {

		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Not Found Insert
		if fetchedNode.isEmpty && nodeInfo.hasUser {

			let newNode = NodeInfoEntity(context: context)
			newNode.id = Int64(nodeInfo.num)
			newNode.num = Int64(nodeInfo.num)
			
			if nodeInfo.hasDeviceMetrics {
				
				let telemetry = TelemetryEntity(context: context)
				
				telemetry.batteryLevel = Int32(nodeInfo.deviceMetrics.batteryLevel)
				telemetry.voltage = nodeInfo.deviceMetrics.voltage
				telemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
				telemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx
				
				var newTelemetries = [TelemetryEntity]()
				newTelemetries.append(telemetry)
				newNode.telemetries? = NSOrderedSet(array: newTelemetries)
			}
			
			newNode.lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			newNode.snr = nodeInfo.snr
			
			if nodeInfo.hasUser {

				let newUser = UserEntity(context: context)
				newUser.userId = nodeInfo.user.id
				newUser.num = Int64(nodeInfo.num)
				newUser.longName = nodeInfo.user.longName
				newUser.shortName = nodeInfo.user.shortName
				newUser.macaddr = nodeInfo.user.macaddr
				newUser.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
				newNode.user = newUser
			}

			if nodeInfo.position.latitudeI > 0 || nodeInfo.position.longitudeI > 0 {
				
				let position = PositionEntity(context: context)
				position.latitudeI = nodeInfo.position.latitudeI
				position.longitudeI = nodeInfo.position.longitudeI
				position.altitude = nodeInfo.position.altitude
				position.satsInView = Int32(nodeInfo.position.satsInView)
				position.time = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.position.time)))
				
				var newPostions = [PositionEntity]()
				newPostions.append(position)
				newNode.positions? = NSOrderedSet(array: newPostions)
			}

			// Look for a MyInfo
			let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
			fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			do {

				let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
				if fetchedMyInfo.count > 0 {
					newNode.myInfo = fetchedMyInfo[0]
				}
				
				do {

					try context.save()
					
					if nodeInfo.hasUser {

						if meshLogging { MeshLogger.log("💾 BLE FROMRADIO received and nodeInfo inserted for \(nodeInfo.user.longName)") }

					} else {

						if meshLogging { MeshLogger.log("💾 BLE FROMRADIO received and nodeInfo inserted for \(nodeInfo.num)") }
					}
					return newNode

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Saving Core Data NodeInfoEntity: \(nsError)")
				}

			} catch {
				print("💥 Fetch MyInfo Error")
			}

		} else if nodeInfo.hasUser && nodeInfo.num > 0 {

			fetchedNode[0].id = Int64(nodeInfo.num)
			fetchedNode[0].num = Int64(nodeInfo.num)
			fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.lastHeard)))
			fetchedNode[0].snr = nodeInfo.snr
			

			if nodeInfo.hasUser {

				fetchedNode[0].user!.userId = nodeInfo.user.id
				fetchedNode[0].user!.num = Int64(nodeInfo.num)
				fetchedNode[0].user!.longName = nodeInfo.user.longName
				fetchedNode[0].user!.shortName = nodeInfo.user.shortName
				fetchedNode[0].user!.macaddr = nodeInfo.user.macaddr
				fetchedNode[0].user!.hwModel = String(describing: nodeInfo.user.hwModel).uppercased()
			}

			if nodeInfo.hasDeviceMetrics {
				
				let newTelemetry = TelemetryEntity(context: context)

				newTelemetry.batteryLevel = Int32(nodeInfo.deviceMetrics.batteryLevel)
				newTelemetry.voltage = nodeInfo.deviceMetrics.voltage
				newTelemetry.channelUtilization = nodeInfo.deviceMetrics.channelUtilization
				newTelemetry.airUtilTx = nodeInfo.deviceMetrics.airUtilTx
				
				let mutableTelemetries = fetchedNode[0].telemetries!.mutableCopy() as! NSMutableOrderedSet
				fetchedNode[0].telemetries = mutableTelemetries.copy() as? NSOrderedSet
			}
			
			if nodeInfo.hasPosition {

				let position = PositionEntity(context: context)
				position.latitudeI = nodeInfo.position.latitudeI
				position.longitudeI = nodeInfo.position.longitudeI
				position.altitude = nodeInfo.position.altitude
				position.satsInView = Int32(nodeInfo.position.satsInView)
				position.time = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.position.time)))

				let mutablePositions = fetchedNode[0].positions!.mutableCopy() as! NSMutableOrderedSet

				fetchedNode[0].positions = mutablePositions.copy() as? NSOrderedSet
				
			}

			// Look for a MyInfo
			let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
			fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(nodeInfo.num))

			do {

				let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
				if fetchedMyInfo.count > 0 {

					fetchedNode[0].myInfo = fetchedMyInfo[0]
				}
				
				do {

					try context.save()
					
					if nodeInfo.hasUser {

						if meshLogging { MeshLogger.log("💾 BLE FROMRADIO received and nodeInfo inserted for \(nodeInfo.user.longName)") }

					} else {

						if meshLogging { MeshLogger.log("💾 BLE FROMRADIO received and nodeInfo inserted for \(nodeInfo.num)") }
					}
					
					return fetchedNode[0]

				} catch {

					context.rollback()

					let nsError = error as NSError
					print("💥 Error Saving Core Data NodeInfoEntity: \(nsError)")
				}

			} catch {
				print("💥 Fetch MyInfo Error")
			}
		}

	} catch {

		print("💥 Fetch NodeInfoEntity Error")
	}
	
	return nil
}

func nodeInfoAppPacket (packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {

	let fetchNodeInfoAppRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoAppRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

	do {

		let fetchedNode = try context.fetch(fetchNodeInfoAppRequest) as! [NodeInfoEntity]

		if fetchedNode.count == 1 {
			fetchedNode[0].id = Int64(packet.from)
			fetchedNode[0].num = Int64(packet.from)
			fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
			fetchedNode[0].snr = packet.rxSnr
			
			if let nodeInfoMessage = try? NodeInfo(serializedData: packet.decoded.payload) {
		
				if nodeInfoMessage.hasDeviceMetrics {
					
					let telemetry = TelemetryEntity(context: context)
					
					telemetry.batteryLevel = Int32(nodeInfoMessage.deviceMetrics.batteryLevel)
					telemetry.voltage = nodeInfoMessage.deviceMetrics.voltage
					telemetry.channelUtilization = nodeInfoMessage.deviceMetrics.channelUtilization
					telemetry.airUtilTx = nodeInfoMessage.deviceMetrics.airUtilTx
					
					var newTelemetries = [TelemetryEntity]()
					newTelemetries.append(telemetry)
					fetchedNode[0].telemetries? = NSOrderedSet(array: newTelemetries)
				}
			}
			
		}
		
		do {

			try context.save()

			if meshLogging { MeshLogger.log("💾 Updated NodeInfo SNR \(packet.rxSnr) and Time from Node Info App Packet For: \(fetchedNode[0].num)")}

		} catch {

			context.rollback()

			let nsError = error as NSError
			print("💥 Error Saving NodeInfoEntity from NODEINFO_APP \(nsError)")

		}
	} catch {

		print("💥 Error Fetching NodeInfoEntity for NODEINFO_APP")
	}
}

func adminAppPacket (packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {
	
    if let deviceConfig = try? Config.DeviceConfig(serializedData: packet.decoded.payload) {
		
		print(try! deviceConfig.jsonString())
		
	} else if let displayConfig = try? Config.DisplayConfig(serializedData: packet.decoded.payload) {
		
		print(try! displayConfig.jsonUTF8Data())
		print(displayConfig.gpsFormat)
		
	} else if let loraConfig = try? Config.LoRaConfig(serializedData: packet.decoded.payload) {
		
		print(try! loraConfig.jsonUTF8Data())
		print(loraConfig.region)
		
	} else if let positionConfig = try? Config.PositionConfig(serializedData: packet.decoded.payload) {
		
		print(try! positionConfig.jsonUTF8Data())
		print(positionConfig.positionBroadcastSecs)
		
	} else if let powerConfig = try? Config.PowerConfig(serializedData: packet.decoded.payload) {
		
		print(try! powerConfig.jsonUTF8Data())
		
	}
	

	if meshLogging { MeshLogger.log("ℹ️ MESH PACKET received for Admin App UNHANDLED \(try! packet.jsonString())") }

}

func positionPacket (packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {
	
	let fetchNodePositionRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodePositionRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))
	
	do {
		
		if let positionMessage = try? Position(serializedData: packet.decoded.payload) {
			
			// Don't save empty position packets
			if positionMessage.longitudeI > 0 || positionMessage.latitudeI > 0 {
				
				let fetchedNode = try context.fetch(fetchNodePositionRequest) as! [NodeInfoEntity]

				if fetchedNode.count == 1 {
			
					let position = PositionEntity(context: context)
					position.latitudeI = positionMessage.latitudeI
					position.longitudeI = positionMessage.longitudeI
					position.altitude = positionMessage.altitude
					position.satsInView = Int32(positionMessage.satsInView)
					position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))

					let mutablePositions = fetchedNode[0].positions!.mutableCopy() as! NSMutableOrderedSet
					mutablePositions.add(position)
				
					fetchedNode[0].id = Int64(packet.from)
					fetchedNode[0].num = Int64(packet.from)
					fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))
					fetchedNode[0].snr = packet.rxSnr
					fetchedNode[0].positions = mutablePositions.copy() as? NSOrderedSet
					
					do {

						try context.save()

						if meshLogging {
							MeshLogger.log("💾 Updated Node Position Coordinates, SNR and Time from Position App Packet For: \(fetchedNode[0].num)")
						}

					} catch {

						context.rollback()

						let nsError = error as NSError
						print("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError)")
					}
				}
				
			} else {
				
				print("💥 Empty POSITION_APP Packet")
			}
		}

	} catch {

		print("💥 Error Fetching NodeInfoEntity for POSITION_APP")
	}
}

func routingPacket (packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {
	
	if let routingMessage = try? Routing(serializedData: packet.decoded.payload) {
		
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
			default: ()
		}
		
		if meshLogging { MeshLogger.log("🕸️ ROUTING PACKET received for RequestID: \(packet.decoded.requestID) Error: \(errorExplanation)") }
						
			
		let fetchMessageRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
		fetchMessageRequest.predicate = NSPredicate(format: "messageId == %lld", Int64(packet.decoded.requestID))

		do {

			let fetchedMessage = try context.fetch(fetchMessageRequest) as? [MessageEntity]
			
			if fetchedMessage?.count ?? 0 > 0 {
				
				fetchedMessage![0].ackError = Int32(routingMessage.errorReason.rawValue)
				
				if routingMessage.errorReason == Routing.Error.none {
					
					fetchedMessage![0].receivedACK = true
				}
				fetchedMessage![0].ackSNR = packet.rxSnr
				fetchedMessage![0].ackTimestamp = Int32(packet.rxTime)
				fetchedMessage![0].objectWillChange.send()
				fetchedMessage![0].fromUser?.objectWillChange.send()
				fetchedMessage![0].toUser?.objectWillChange.send()
				
			} else {
				
				return
			}
			
			try context.save()

			  if meshLogging {
				  MeshLogger.log("💾 ACK Received and saved for MessageID \(packet.decoded.requestID)")
			  }
			
		} catch {
			
			context.rollback()

			let nsError = error as NSError
			print("💥 Error Saving ACK for message MessageID \(packet.id) Error: \(nsError)")
		}
		
	}
}
	
func telemetryPacket(packet: MeshPacket, meshLogging: Bool, context: NSManagedObjectContext) {
	
	if let telemetryMessage = try? Telemetry(serializedData: packet.decoded.payload) {
		
			let telemetry = TelemetryEntity(context: context)
		
		let fetchNodeTelemetryRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeTelemetryRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))

		do {

			let fetchedNode = try context.fetch(fetchNodeTelemetryRequest) as! [NodeInfoEntity]

			if fetchedNode.count == 1 {
				
				if telemetryMessage.variant == Telemetry.OneOf_Variant.deviceMetrics(telemetryMessage.deviceMetrics) {
					
					// Device Metrics
					telemetry.airUtilTx = telemetryMessage.deviceMetrics.airUtilTx
					telemetry.channelUtilization = telemetryMessage.deviceMetrics.channelUtilization
					telemetry.batteryLevel = Int32(telemetryMessage.deviceMetrics.batteryLevel)
					telemetry.voltage = telemetryMessage.deviceMetrics.voltage
					telemetry.metricsType = 0
					
				} else if telemetryMessage.variant == Telemetry.OneOf_Variant.environmentMetrics(telemetryMessage.environmentMetrics) {
				
					// Environment Metrics
					telemetry.barometricPressure = telemetryMessage.environmentMetrics.barometricPressure
					telemetry.current = telemetryMessage.environmentMetrics.current
					telemetry.gasResistance = telemetryMessage.environmentMetrics.gasResistance
					telemetry.relativeHumidity = telemetryMessage.environmentMetrics.relativeHumidity
					telemetry.temperature = telemetryMessage.environmentMetrics.temperature
					telemetry.current = telemetryMessage.environmentMetrics.current
					telemetry.voltage = telemetryMessage.environmentMetrics.voltage
					telemetry.metricsType = 1
					
				}
				telemetry.time = Date(timeIntervalSince1970: TimeInterval(Int64(telemetryMessage.time)))
				let mutableTelemetries = fetchedNode[0].telemetries!.mutableCopy() as! NSMutableOrderedSet
				mutableTelemetries.add(telemetry)
				
				fetchedNode[0].lastHeard = telemetry.time
				fetchedNode[0].telemetries = mutableTelemetries.copy() as? NSOrderedSet
			}
			
			try context.save()

			  if meshLogging {
				  MeshLogger.log("💾 Telemetry Saved for Node: \(packet.from)")
			  }
			
		} catch {
			
			context.rollback()

			let nsError = error as NSError
			print("💥 Error Saving Telemetry for Node \(packet.from) Error: \(nsError)")
		}
		
	} else {
		
	}
}

func textMessageAppPacket(packet: MeshPacket, connectedNode: Int64, meshLogging: Bool, context: NSManagedObjectContext) {
	
	let broadcastNodeNum: UInt32 = 4294967295
		
	if let messageText = String(bytes: packet.decoded.payload, encoding: .utf8) {

		if meshLogging { MeshLogger.log("💬 Message received for text message app") }

		let messageUsers: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
		messageUsers.predicate = NSPredicate(format: "num IN %@", [packet.to, packet.from])

		do {

			let fetchedUsers = try context.fetch(messageUsers) as! [UserEntity]

			let newMessage = MessageEntity(context: context)
			newMessage.messageId = Int64(packet.id)
			newMessage.messageTimestamp = Int32(bitPattern: packet.rxTime)
			newMessage.receivedACK = false
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
			newMessage.fromUser?.objectWillChange.send()
			newMessage.toUser?.objectWillChange.send()
			
				var messageSaved = false

				do {

					try context.save()

					if meshLogging { MeshLogger.log("💾 Saved a new message for \(newMessage.messageId)") }
					
					messageSaved = true
					
					if messageSaved { //&& (newMessage.toUser != nil && newMessage.toUser!.num == broadcastNodeNum || connectedNode == newMessage.toUser!.num) {
					
						
						if newMessage.fromUser != nil {
							
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
							
							if meshLogging { MeshLogger.log("💬 iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? "Unknown")") }
						}
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
