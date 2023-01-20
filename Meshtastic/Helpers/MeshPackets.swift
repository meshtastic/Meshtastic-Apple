//
//  MeshPackets.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/27/22.
//

import Foundation
import CoreData
import SwiftUI

func generateMessageMarkdown (message: String) -> String {
	
	let types: NSTextCheckingResult.CheckingType = [.address, .link, .phoneNumber]
	let detector = try! NSDataDetector(types: types.rawValue)
	let matches = detector.matches(in: message, options: [], range: NSRange(location: 0, length: message.utf16.count))
	var messageWithMarkdown = message
	if matches.count > 0 {
		
		for match in matches {
			guard let range = Range(match.range, in: message) else { continue }
			if match.resultType == .address {
				let address = message[range]
				let urlEncodedAddress = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
				messageWithMarkdown = messageWithMarkdown.replacingOccurrences(of: address, with: "[\(address)](http://maps.apple.com/?address=\(urlEncodedAddress ?? ""))")
			} else if match.resultType == .phoneNumber {
				let phone = messageWithMarkdown[range]
				messageWithMarkdown = messageWithMarkdown.replacingOccurrences(of: phone, with: "[\(phone)](tel:\(phone))")
			} else if match.resultType == .link {
				let url = messageWithMarkdown[range]
				let absoluteUrl = match.url?.absoluteString ?? ""
				messageWithMarkdown = messageWithMarkdown.replacingOccurrences(of: url, with: "[\(String(match.url?.host ?? "Link"))\(String(match.url?.path ?? ""))](\(absoluteUrl))")
			}
		}
	}
	return messageWithMarkdown
}

func localConfig (config: Config, context:NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {
	
	// We don't care about any of the Power settings, config is available for everyting else
	if config.payloadVariant == Config.OneOf_PayloadVariant.bluetooth(config.bluetooth) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.bluetooth.config %@", comment: "Bluetooth config received: %@"), String(nodeNum))
		MeshLogger.log("📶 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].bluetoothConfig == nil {
					let newBluetoothConfig = BluetoothConfigEntity(context: context)
					newBluetoothConfig.enabled = config.bluetooth.enabled
					newBluetoothConfig.mode = Int32(config.bluetooth.mode.rawValue)
					newBluetoothConfig.fixedPin = Int32(config.bluetooth.fixedPin)
					fetchedNode[0].bluetoothConfig = newBluetoothConfig
				} else {
					fetchedNode[0].bluetoothConfig?.enabled = config.bluetooth.enabled
					fetchedNode[0].bluetoothConfig?.mode = Int32(config.bluetooth.mode.rawValue)
					fetchedNode[0].bluetoothConfig?.fixedPin = Int32(config.bluetooth.fixedPin)
				}
				do {
					try context.save()
					print("💾 Updated Bluetooth Config for node number: \(String(nodeNum))")
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
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.device(config.device) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.device.config %@", comment: "Device config received: %@"), String(nodeNum))
		MeshLogger.log("📟 \(logString)")
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].deviceConfig == nil {
					let newDeviceConfig = DeviceConfigEntity(context: context)
					newDeviceConfig.role = Int32(config.device.role.rawValue)
					newDeviceConfig.serialEnabled = config.device.serialEnabled
					newDeviceConfig.debugLogEnabled = config.device.debugLogEnabled
					newDeviceConfig.buttonGpio = Int32(config.device.buttonGpio)
					newDeviceConfig.buzzerGpio =  Int32(config.device.buzzerGpio)
					fetchedNode[0].deviceConfig = newDeviceConfig
				} else {
					fetchedNode[0].deviceConfig?.role = Int32(config.device.role.rawValue)
					fetchedNode[0].deviceConfig?.serialEnabled = config.device.serialEnabled
					fetchedNode[0].deviceConfig?.debugLogEnabled = config.device.debugLogEnabled
					fetchedNode[0].deviceConfig?.buttonGpio = Int32(config.device.buttonGpio)
					fetchedNode[0].deviceConfig?.buzzerGpio = Int32(config.device.buzzerGpio)
				}
				do {
					try context.save()
					print("💾 Updated Device Config for node number: \(String(nodeNum))")
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Updating Core Data DeviceConfigEntity: \(nsError)")
				}
			}
		} catch {
			let nsError = error as NSError
			print("💥 Fetching node for core data DeviceConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.display(config.display) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.display.config %@", comment: "Display config received: %@"), String(nodeNum))
		MeshLogger.log("🖥️ \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].displayConfig == nil {
					
					let newDisplayConfig = DisplayConfigEntity(context: context)
					newDisplayConfig.gpsFormat = Int32(config.display.gpsFormat.rawValue)
					newDisplayConfig.screenOnSeconds = Int32(config.display.screenOnSecs)
					newDisplayConfig.screenCarouselInterval = Int32(config.display.autoScreenCarouselSecs)
					newDisplayConfig.compassNorthTop = config.display.compassNorthTop
					newDisplayConfig.flipScreen = config.display.flipScreen
					newDisplayConfig.oledType = Int32(config.display.oled.rawValue)
					fetchedNode[0].displayConfig = newDisplayConfig
					
				} else {
					
					fetchedNode[0].displayConfig?.gpsFormat = Int32(config.display.gpsFormat.rawValue)
					fetchedNode[0].displayConfig?.screenOnSeconds = Int32(config.display.screenOnSecs)
					fetchedNode[0].displayConfig?.screenCarouselInterval = Int32(config.display.autoScreenCarouselSecs)
					fetchedNode[0].displayConfig?.compassNorthTop = config.display.compassNorthTop
					fetchedNode[0].displayConfig?.flipScreen = config.display.flipScreen
					fetchedNode[0].displayConfig?.oledType = Int32(config.display.oled.rawValue)
				}
				
				do {
					
					try context.save()
					print("💾 Updated Display Config for node number: \(String(nodeNum))")
					
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
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.lora.config %@", comment: "LoRa config received: %@"), String(nodeNum))
		MeshLogger.log("📻 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save LoRa Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].loRaConfig == nil {
					let newLoRaConfig = LoRaConfigEntity(context: context)
					newLoRaConfig.regionCode = Int32(config.lora.region.rawValue)
					newLoRaConfig.usePreset = config.lora.usePreset
					newLoRaConfig.modemPreset = Int32(config.lora.modemPreset.rawValue)
					newLoRaConfig.bandwidth = Int32(config.lora.bandwidth)
					newLoRaConfig.spreadFactor = Int32(config.lora.spreadFactor)
					newLoRaConfig.codingRate = Int32(config.lora.codingRate)
					newLoRaConfig.frequencyOffset = config.lora.frequencyOffset
					newLoRaConfig.hopLimit = Int32(config.lora.hopLimit)
					newLoRaConfig.txPower = Int32(config.lora.txPower)
					newLoRaConfig.txEnabled = config.lora.txEnabled
					newLoRaConfig.channelNum = Int32(config.lora.channelNum)
					fetchedNode[0].loRaConfig = newLoRaConfig
				} else {
					fetchedNode[0].loRaConfig?.regionCode = Int32(config.lora.region.rawValue)
					fetchedNode[0].loRaConfig?.usePreset = config.lora.usePreset
					fetchedNode[0].loRaConfig?.modemPreset = Int32(config.lora.modemPreset.rawValue)
					fetchedNode[0].loRaConfig?.bandwidth = Int32(config.lora.bandwidth)
					fetchedNode[0].loRaConfig?.spreadFactor = Int32(config.lora.spreadFactor)
					fetchedNode[0].loRaConfig?.codingRate = Int32(config.lora.codingRate)
					fetchedNode[0].loRaConfig?.frequencyOffset = config.lora.frequencyOffset
					fetchedNode[0].loRaConfig?.hopLimit = Int32(config.lora.hopLimit)
					fetchedNode[0].loRaConfig?.txPower = Int32(config.lora.txPower)
					fetchedNode[0].loRaConfig?.txEnabled = config.lora.txEnabled
					fetchedNode[0].loRaConfig?.channelNum = Int32(config.lora.channelNum)
				}
				do {
					try context.save()
					print("💾 Updated LoRa Config for node number: \(String(nodeNum))")
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
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.network(config.network) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.network.config %@", comment: "Network config received: %@"), String(nodeNum))
		MeshLogger.log("🌐 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save WiFi Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].networkConfig == nil {
					let newNetworkConfig = NetworkConfigEntity(context: context)
					newNetworkConfig.wifiSsid = config.network.wifiSsid
					newNetworkConfig.wifiPsk = config.network.wifiPsk
					fetchedNode[0].networkConfig = newNetworkConfig
				} else {
					fetchedNode[0].networkConfig?.wifiSsid = config.network.wifiSsid
					fetchedNode[0].networkConfig?.wifiPsk = config.network.wifiPsk
				}
				
				do {
					try context.save()
					print("💾 Updated Network Config for node number: \(String(nodeNum))")
					
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Updating Core Data WiFiConfigEntity: \(nsError)")
				}
			} else {
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save Network Config")
			}
		} catch {
			let nsError = error as NSError
			print("💥 Fetching node for core data NetworkConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == Config.OneOf_PayloadVariant.position(config.position) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.position.config %@", comment: "Positon config received: %@"), String(nodeNum))
		MeshLogger.log("🗺️ \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save LoRa Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].positionConfig == nil {
					let newPositionConfig = PositionConfigEntity(context: context)
					newPositionConfig.smartPositionEnabled = config.position.positionBroadcastSmartEnabled
					newPositionConfig.deviceGpsEnabled = config.position.gpsEnabled
					newPositionConfig.fixedPosition = config.position.fixedPosition
					newPositionConfig.gpsUpdateInterval = Int32(config.position.gpsUpdateInterval)
					newPositionConfig.gpsAttemptTime = Int32(config.position.gpsAttemptTime)
					newPositionConfig.positionBroadcastSeconds = Int32(config.position.positionBroadcastSecs)
					newPositionConfig.positionFlags = Int32(config.position.positionFlags)
					fetchedNode[0].positionConfig = newPositionConfig
				} else {
					fetchedNode[0].positionConfig?.smartPositionEnabled = config.position.positionBroadcastSmartEnabled
					fetchedNode[0].positionConfig?.deviceGpsEnabled = config.position.gpsEnabled
					fetchedNode[0].positionConfig?.fixedPosition = config.position.fixedPosition
					fetchedNode[0].positionConfig?.gpsUpdateInterval = Int32(config.position.gpsUpdateInterval)
					fetchedNode[0].positionConfig?.gpsAttemptTime = Int32(config.position.gpsAttemptTime)
					fetchedNode[0].positionConfig?.positionBroadcastSeconds = Int32(config.position.positionBroadcastSecs)
					fetchedNode[0].positionConfig?.positionFlags = Int32(config.position.positionFlags)
				}
				do {
					try context.save()
					print("💾 Updated Position Config for node number: \(String(nodeNum))")
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
}

func moduleConfig (config: ModuleConfig, context:NSManagedObjectContext, nodeNum: Int64, nodeLongName: String) {
	
	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.cannedMessage(config.cannedMessage) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.cannedmessage.config %@", comment: "Canned Message module config received: %@"), String(nodeNum))
		MeshLogger.log("🥫 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			
			// Found a node, save Canned Message Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].cannedMessageConfig == nil {
					
					let newCannedMessageConfig = CannedMessageConfigEntity(context: context)
					
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
					
					fetchedNode[0].cannedMessageConfig = newCannedMessageConfig
					
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
				
				do {
					try context.save()
					print("💾 Updated Canned Message Module Config for node number: \(String(nodeNum))")
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
		
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.externalnotification.config %@", comment: "External Notifiation module config received: %@"), String(nodeNum))
		MeshLogger.log("📣 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save External Notificaitone Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].externalNotificationConfig == nil {
					let newExternalNotificationConfig = ExternalNotificationConfigEntity(context: context)
					newExternalNotificationConfig.enabled = config.externalNotification.enabled
					newExternalNotificationConfig.usePWM = config.externalNotification.usePwm
					newExternalNotificationConfig.alertBell = config.externalNotification.alertBell
					newExternalNotificationConfig.alertBellBuzzer = config.externalNotification.alertBellBuzzer
					newExternalNotificationConfig.alertBellVibra = config.externalNotification.alertBellVibra
					newExternalNotificationConfig.alertMessage = config.externalNotification.alertMessage
					newExternalNotificationConfig.alertMessageBuzzer = config.externalNotification.alertMessageBuzzer
					newExternalNotificationConfig.alertMessageVibra = config.externalNotification.alertMessageVibra
					newExternalNotificationConfig.active = config.externalNotification.active
					newExternalNotificationConfig.output = Int32(config.externalNotification.output)
					newExternalNotificationConfig.outputBuzzer = Int32(config.externalNotification.outputBuzzer)
					newExternalNotificationConfig.outputVibra = Int32(config.externalNotification.outputVibra)
					newExternalNotificationConfig.outputMilliseconds = Int32(config.externalNotification.outputMs)
					newExternalNotificationConfig.nagTimeout = Int32(config.externalNotification.nagTimeout)
					fetchedNode[0].externalNotificationConfig = newExternalNotificationConfig
					
				} else {
					fetchedNode[0].externalNotificationConfig?.enabled = config.externalNotification.enabled
					fetchedNode[0].externalNotificationConfig?.usePWM = config.externalNotification.usePwm
					fetchedNode[0].externalNotificationConfig?.alertBell = config.externalNotification.alertBell
					fetchedNode[0].externalNotificationConfig?.alertBellBuzzer = config.externalNotification.alertBellBuzzer
					fetchedNode[0].externalNotificationConfig?.alertBellVibra = config.externalNotification.alertBellVibra
					fetchedNode[0].externalNotificationConfig?.alertMessage = config.externalNotification.alertMessage
					fetchedNode[0].externalNotificationConfig?.alertMessageBuzzer = config.externalNotification.alertMessageBuzzer
					fetchedNode[0].externalNotificationConfig?.alertMessageVibra = config.externalNotification.alertMessageVibra
					fetchedNode[0].externalNotificationConfig?.active = config.externalNotification.active
					fetchedNode[0].externalNotificationConfig?.output = Int32(config.externalNotification.output)
					fetchedNode[0].externalNotificationConfig?.outputBuzzer = Int32(config.externalNotification.outputBuzzer)
					fetchedNode[0].externalNotificationConfig?.outputVibra = Int32(config.externalNotification.outputVibra)
					fetchedNode[0].externalNotificationConfig?.outputMilliseconds = Int32(config.externalNotification.outputMs)
					fetchedNode[0].externalNotificationConfig?.nagTimeout = Int32(config.externalNotification.nagTimeout)
				}
				
				do {
					try context.save()
					print("💾 Updated External Notification Module Config for node number: \(String(nodeNum))")
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
	
	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.mqtt(config.mqtt) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.mqtt.config %@", comment: "MQTT module config received: %@"), String(nodeNum))
		MeshLogger.log("🌉 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save MQTT Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].mqttConfig == nil {
					let newMQTTConfig = MQTTConfigEntity(context: context)
					newMQTTConfig.enabled = config.mqtt.enabled
					newMQTTConfig.address = config.mqtt.address
					newMQTTConfig.address = config.mqtt.username
					newMQTTConfig.password = config.mqtt.password
					newMQTTConfig.encryptionEnabled = config.mqtt.encryptionEnabled
					newMQTTConfig.jsonEnabled = config.mqtt.jsonEnabled
					fetchedNode[0].mqttConfig = newMQTTConfig
				} else {
					fetchedNode[0].mqttConfig?.enabled = config.mqtt.enabled
					fetchedNode[0].mqttConfig?.address = config.mqtt.address
					fetchedNode[0].mqttConfig?.address = config.mqtt.username
					fetchedNode[0].mqttConfig?.password = config.mqtt.password
					fetchedNode[0].mqttConfig?.encryptionEnabled = config.mqtt.encryptionEnabled
					fetchedNode[0].mqttConfig?.jsonEnabled = config.mqtt.jsonEnabled
				}
				do {
					try context.save()
					print("💾 Updated MQTT Config for node number: \(String(nodeNum))")
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Updating Core Data MQTTConfigEntity: \(nsError)")
				}
			} else {
				print("💥 No Nodes found in local database matching node number \(nodeNum) unable to save MQTT Module Config")
			}
		} catch {
			let nsError = error as NSError
			print("💥 Fetching node for core data MQTTConfigEntity failed: \(nsError)")
		}
	}
	
	if config.payloadVariant == ModuleConfig.OneOf_PayloadVariant.rangeTest(config.rangeTest) {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.rangetest.config %@", comment: "Range Test module config received: %@"), String(nodeNum))
		MeshLogger.log("⛰️ \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				if fetchedNode[0].rangeTestConfig == nil {
					let newRangeTestConfig = RangeTestConfigEntity(context: context)
					newRangeTestConfig.sender = Int32(config.rangeTest.sender)
					newRangeTestConfig.enabled = config.rangeTest.enabled
					newRangeTestConfig.save = config.rangeTest.save
					fetchedNode[0].rangeTestConfig = newRangeTestConfig
				} else {
					fetchedNode[0].rangeTestConfig?.sender = Int32(config.rangeTest.sender)
					fetchedNode[0].rangeTestConfig?.enabled = config.rangeTest.enabled
					fetchedNode[0].rangeTestConfig?.save = config.rangeTest.save
				}
				do {
					try context.save()
					print("💾 Updated Range Test Config for node number: \(String(nodeNum))")
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
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.serial.config %@", comment: "Serial module config received: %@"), String(nodeNum))
		MeshLogger.log("🤖 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			
			// Found a node, save Device Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].serialConfig == nil {
					
					let newSerialConfig = SerialConfigEntity(context: context)
					newSerialConfig.enabled = config.serial.enabled
					newSerialConfig.echo = config.serial.echo
					newSerialConfig.rxd = Int32(config.serial.rxd)
					newSerialConfig.txd = Int32(config.serial.txd)
					newSerialConfig.baudRate = Int32(config.serial.baud.rawValue)
					newSerialConfig.timeout = Int32(config.serial.timeout)
					newSerialConfig.mode = Int32(config.serial.mode.rawValue)
					fetchedNode[0].serialConfig = newSerialConfig
					
				} else {
					fetchedNode[0].serialConfig?.enabled = config.serial.enabled
					fetchedNode[0].serialConfig?.echo = config.serial.echo
					fetchedNode[0].serialConfig?.rxd = Int32(config.serial.rxd)
					fetchedNode[0].serialConfig?.txd = Int32(config.serial.txd)
					fetchedNode[0].serialConfig?.baudRate = Int32(config.serial.baud.rawValue)
					fetchedNode[0].serialConfig?.timeout = Int32(config.serial.timeout)
					fetchedNode[0].serialConfig?.mode = Int32(config.serial.mode.rawValue)
				}
				
				do {
					try context.save()
					print("💾 Updated Serial Module Config for node number: \(String(nodeNum))")
					
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
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.telemetry.config %@", comment: "Telemetry module config received: %@"), String(nodeNum))
		MeshLogger.log("📈 \(logString)")
		
		let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
		
		do {
			
			let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
			// Found a node, save Telemetry Config
			if !fetchedNode.isEmpty {
				
				if fetchedNode[0].telemetryConfig == nil {
					
					let newTelemetryConfig = TelemetryConfigEntity(context: context)
					
					newTelemetryConfig.deviceUpdateInterval = Int32(config.telemetry.deviceUpdateInterval)
					newTelemetryConfig.environmentUpdateInterval = Int32(config.telemetry.environmentUpdateInterval)
					newTelemetryConfig.environmentMeasurementEnabled = config.telemetry.environmentMeasurementEnabled
					newTelemetryConfig.environmentScreenEnabled = config.telemetry.environmentScreenEnabled
					newTelemetryConfig.environmentDisplayFahrenheit = config.telemetry.environmentDisplayFahrenheit
					
					fetchedNode[0].telemetryConfig = newTelemetryConfig
					
				} else {
					
					fetchedNode[0].telemetryConfig?.deviceUpdateInterval = Int32(config.telemetry.deviceUpdateInterval)
					fetchedNode[0].telemetryConfig?.environmentUpdateInterval = Int32(config.telemetry.environmentUpdateInterval)
					fetchedNode[0].telemetryConfig?.environmentMeasurementEnabled = config.telemetry.environmentMeasurementEnabled
					fetchedNode[0].telemetryConfig?.environmentScreenEnabled = config.telemetry.environmentScreenEnabled
					fetchedNode[0].telemetryConfig?.environmentDisplayFahrenheit = config.telemetry.environmentDisplayFahrenheit
				}
				
				do {
					try context.save()
					print("💾 Updated Telemetry Module Config for node number: \(String(nodeNum))")
					
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

func myInfoPacket (myInfo: MyNodeInfo, peripheralId: String, context: NSManagedObjectContext) -> MyInfoEntity? {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.myinfo %@", comment: "MyInfo received: %@"), String(myInfo.myNodeNum))
	MeshLogger.log("ℹ️ \(logString)")
	
	let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
	fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(myInfo.myNodeNum))
	
	do {
		let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
		// Not Found Insert
		if fetchedMyInfo.isEmpty {
			
			let myInfoEntity = MyInfoEntity(context: context)
			myInfoEntity.peripheralId = peripheralId
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
				print("💾 Saved a new myInfo for node number: \(String(myInfo.myNodeNum))")
				return myInfoEntity
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Inserting New Core Data MyInfoEntity: \(nsError)")
			}
		} else {
			
			fetchedMyInfo[0].peripheralId = peripheralId
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
				print("💾 Updated myInfo for node number: \(String(myInfo.myNodeNum))")
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

func channelPacket (channel: Channel, fromNum: Int64, context: NSManagedObjectContext) {
	
	if channel.isInitialized && channel.hasSettings && channel.role != Channel.Role.disabled  {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.channel.received %d %@", comment: "Channel %d received from: %@"), channel.index, String(fromNum))
		MeshLogger.log("🎛️ \(logString)")
		
		let fetchedMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
		fetchedMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", fromNum)
		
		do {
			
			let fetchedMyInfo = try context.fetch(fetchedMyInfoRequest) as! [MyInfoEntity]
			if fetchedMyInfo.count == 1 {
				let newChannel = ChannelEntity(context: context)
				newChannel.id = Int32(channel.index)
				newChannel.index = Int32(channel.index)
				newChannel.uplinkEnabled = channel.settings.uplinkEnabled
				newChannel.downlinkEnabled = channel.settings.downlinkEnabled
				newChannel.name = channel.settings.name
				newChannel.role = Int32(channel.role.rawValue)
				newChannel.psk = channel.settings.psk
				let mutableChannels = fetchedMyInfo[0].channels!.mutableCopy() as! NSMutableOrderedSet
				if mutableChannels.contains(newChannel) {
					mutableChannels.replaceObject(at: Int(newChannel.index), with: newChannel)
				} else {
					mutableChannels.add(newChannel)
				}
				fetchedMyInfo[0].channels = mutableChannels.copy() as? NSOrderedSet
				if newChannel.name?.lowercased() == "admin" {
					fetchedMyInfo[0].adminIndex = newChannel.index
				}
				do {
					try context.save()
				} catch {
					print("Failed to save channel")
				}
				print("💾 Updated MyInfo channel \(channel.index) from Channel App Packet For: \(fetchedMyInfo[0].myNodeNum)")
			} else if channel.role.rawValue > 0 {
				print("💥 Trying to save a channel to a MyInfo that does not exist: \(fromNum)")
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving MyInfo Channel from ADMIN_APP \(nsError)")
		}
	}
}

func deviceMetadataPacket (metadata: DeviceMetadata, fromNum: Int64, context: NSManagedObjectContext) {
	
	if metadata.isInitialized {
		
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.device.metadata.received %@", comment: "Device Metadata received from: %@"), String(fromNum))
		MeshLogger.log("🎛️ \(logString)")
		
		let fetchedNodeRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
		fetchedNodeRequest.predicate = NSPredicate(format: "num == %lld", fromNum)
		
		do {
			
			let fetchedNode = try context.fetch(fetchedNodeRequest) as! [NodeInfoEntity]
			if fetchedNode.count == 1 {
				let newMetadata = DeviceMetadataEntity(context: context)
				newMetadata.firmwareVersion = metadata.firmwareVersion
				newMetadata.deviceStateVersion = Int32(metadata.deviceStateVersion)
				newMetadata.canShutdown = metadata.canShutdown
				newMetadata.hasWifi = metadata.hasWifi_p
				newMetadata.hasBluetooth = metadata.hasBluetooth_p
				newMetadata.hasEthernet	= metadata.hasEthernet_p
				newMetadata.role = Int32(metadata.role.rawValue)
				newMetadata.positionFlags = Int32(metadata.positionFlags)
				
				fetchedNode[0].metadata = newMetadata
				
				do {
					try context.save()
				} catch {
					print("Failed to save device metadata")
				}
				print("💾 Updated Device Metadata from Admin App Packet For: \(fromNum)")
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving MyInfo Channel from ADMIN_APP \(nsError)")
		}
	}
}

func nodeInfoPacket (nodeInfo: NodeInfo, channel: UInt32, context: NSManagedObjectContext) -> NodeInfoEntity? {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.nodeinfo.received %@", comment: "Node info received for: %@"), String(nodeInfo.num))
	MeshLogger.log("📟 \(logString)")
	
	let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeInfo.num))
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
		// Not Found Insert
		if fetchedNode.isEmpty && nodeInfo.hasUser {
			
			let newNode = NodeInfoEntity(context: context)
			newNode.id = Int64(nodeInfo.num)
			newNode.num = Int64(nodeInfo.num)
			newNode.channel = Int32(channel)
			
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
				position.seqNo = Int32(nodeInfo.position.seqNumber)
				position.latitudeI = nodeInfo.position.latitudeI
				position.longitudeI = nodeInfo.position.longitudeI
				position.altitude = nodeInfo.position.altitude
				position.satsInView = Int32(nodeInfo.position.satsInView)
				position.speed = Int32(nodeInfo.position.groundSpeed)
				position.heading = Int32(nodeInfo.position.groundTrack)
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
			fetchedNode[0].channel = Int32(channel)
			
			
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
					print("💾 NodeInfo saved for \(nodeInfo.num)")
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

func nodeInfoAppPacket (packet: MeshPacket, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.nodeinfo.received %@", comment: "Node info received for: %@"), String(packet.from))
	MeshLogger.log("📟 \(logString)")
	
	let fetchNodeInfoAppRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodeInfoAppRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))
	
	do {
		
		let fetchedNode = try context.fetch(fetchNodeInfoAppRequest) as? [NodeInfoEntity] ?? []
		
		if fetchedNode.count == 1 {
			fetchedNode[0].id = Int64(packet.from)
			fetchedNode[0].num = Int64(packet.from)
			fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(packet.rxTime)))
			fetchedNode[0].snr = packet.rxSnr
			fetchedNode[0].channel = Int32(packet.channel)
			
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
				if nodeInfoMessage.hasUser {
					fetchedNode[0].user!.userId = nodeInfoMessage.user.id
					fetchedNode[0].user!.num = Int64(nodeInfoMessage.num)
					fetchedNode[0].user!.longName = nodeInfoMessage.user.longName
					fetchedNode[0].user!.shortName = nodeInfoMessage.user.shortName
					fetchedNode[0].user!.macaddr = nodeInfoMessage.user.macaddr
					fetchedNode[0].user!.hwModel = String(describing: nodeInfoMessage.user.hwModel).uppercased()
				}
			}
			do {
				try context.save()
				print("💾 Updated NodeInfo from Node Info App Packet For: \(fetchedNode[0].num)")
			} catch {
				context.rollback()
				let nsError = error as NSError
				print("💥 Error Saving NodeInfoEntity from NODEINFO_APP \(nsError)")
			}
		} else {
			// New node info not from device but potentially from another network
		}
	} catch {
		print("💥 Error Fetching NodeInfoEntity for NODEINFO_APP")
	}
}

func adminAppPacket (packet: MeshPacket, context: NSManagedObjectContext) {
	
	MeshLogger.log("🕸️ MESH PACKET received for Admin App \(try! packet.decoded.jsonString())")
	
	if let adminMessage = try? AdminMessage(serializedData: packet.decoded.payload) {
		
		MeshLogger.log("🕸️ MESH PACKET received for Admin App \(adminMessage.getDeviceMetadataResponse)")
		
		if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getCannedMessageModuleMessagesResponse(adminMessage.getCannedMessageModuleMessagesResponse) {
			
			if let cmmc = try? CannedMessageModuleConfig(serializedData: packet.decoded.payload) {
				
				if !cmmc.messages.isEmpty {
					
					let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.cannedmessages.messages.received %@", comment: "Canned Messages Messages Received For: %@"), String(packet.from))
					MeshLogger.log("🥫 \(logString)")
					
					let fetchNodeRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
					fetchNodeRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))
					
					do {
						let fetchedNode = try context.fetch(fetchNodeRequest) as! [NodeInfoEntity]
						if fetchedNode.count == 1 {
							let messages =  String(cmmc.textFormatString())
								.replacingOccurrences(of: "11: ", with: "")
								.replacingOccurrences(of: "\"", with: "")
								.trimmingCharacters(in: .whitespacesAndNewlines)
							fetchedNode[0].cannedMessageConfig?.messages = messages
							do {
								try context.save()
								print("💾 Updated Canned Messages Messages For: \(fetchedNode[0].num)")
							} catch {
								context.rollback()
								let nsError = error as NSError
								print("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError)")
							}
						}
					} catch {
						print("💥 Error Deserializing ADMIN_APP packet.")
					}
				}
			}
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getChannelResponse(adminMessage.getChannelResponse) {
			channelPacket(channel: adminMessage.getChannelResponse, fromNum: Int64(packet.from), context: context)
		} else if adminMessage.payloadVariant == AdminMessage.OneOf_PayloadVariant.getDeviceMetadataResponse(adminMessage.getDeviceMetadataResponse) {
			deviceMetadataPacket(metadata: adminMessage.getDeviceMetadataResponse, fromNum: Int64(packet.from), context: context)
			
			print(try! adminMessage.getDeviceMetadataResponse.jsonString())
			
			
		}
	}
}

func positionPacket (packet: MeshPacket, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.position.received %@", comment: "Position Packet received from node: %@"), String(packet.from))
	MeshLogger.log("📍 \(logString)")
	
	let fetchNodePositionRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
	fetchNodePositionRequest.predicate = NSPredicate(format: "num == %lld", Int64(packet.from))
	
	do {
		
		if let positionMessage = try? Position(serializedData: packet.decoded.payload) {
			// Don't save empty position packets
			if positionMessage.longitudeI > 0 || positionMessage.latitudeI > 0 {
				let fetchedNode = try context.fetch(fetchNodePositionRequest) as! [NodeInfoEntity]
				if fetchedNode.count == 1 {
					
					let position = PositionEntity(context: context)
					position.snr = packet.rxSnr
					position.seqNo = Int32(positionMessage.seqNumber)
					position.latitudeI = positionMessage.latitudeI
					position.longitudeI = positionMessage.longitudeI
					position.altitude = positionMessage.altitude
					position.satsInView = Int32(positionMessage.satsInView)
					position.speed = Int32(positionMessage.groundSpeed)
					position.heading = Int32(positionMessage.groundTrack)
					if positionMessage.timestamp != 0 {
						position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.timestamp)))
					} else {
						position.time = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))
					}
					let mutablePositions = fetchedNode[0].positions!.mutableCopy() as! NSMutableOrderedSet
					mutablePositions.add(position)
					fetchedNode[0].id = Int64(packet.from)
					fetchedNode[0].num = Int64(packet.from)
					fetchedNode[0].lastHeard = Date(timeIntervalSince1970: TimeInterval(Int64(positionMessage.time)))
					fetchedNode[0].snr = packet.rxSnr
					fetchedNode[0].positions = mutablePositions.copy() as? NSOrderedSet
					do {
						try context.save()
						print("💾 Updated Node Position Coordinates, SNR and Time from Position App Packet For: \(fetchedNode[0].num)")
					} catch {
						context.rollback()
						let nsError = error as NSError
						print("💥 Error Saving NodeInfoEntity from POSITION_APP \(nsError)")
					}
				}
			} else {
				print("💥 Empty POSITION_APP Packet")
				print(try! packet.jsonString())
			}
		}
	} catch {
		print("💥 Error Deserializing POSITION_APP packet.")
	}
}

func routingPacket (packet: MeshPacket, connectedNodeNum: Int64, context: NSManagedObjectContext) {
	
	if let routingMessage = try? Routing(serializedData: packet.decoded.payload) {
		
		let routingError = RoutingError(rawValue: routingMessage.errorReason.rawValue)
		
		let routingErrorString = routingError?.display ?? NSLocalizedString("unknown", comment: "")
		let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.routing.message %@ %@", comment: "Routing received for RequestID: %@ Ack Status: %@"), String(packet.decoded.requestID), routingErrorString)
		MeshLogger.log("🕸️ \(logString)")
		
		let fetchMessageRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MessageEntity")
		fetchMessageRequest.predicate = NSPredicate(format: "messageId == %lld", Int64(packet.decoded.requestID))
		
		do {
			let fetchedMessage = try context.fetch(fetchMessageRequest) as? [MessageEntity]
			if fetchedMessage?.count ?? 0 > 0 {
				
				if fetchedMessage![0].toUser != nil {
					// Real ACK from DM Recipient
					if packet.to != packet.from {
						fetchedMessage![0].realACK = true
					}
				}
				fetchedMessage![0].ackError = Int32(routingMessage.errorReason.rawValue)
				
				if routingMessage.errorReason == Routing.Error.none {
					
					fetchedMessage![0].receivedACK = true
				}
				fetchedMessage![0].ackSNR = packet.rxSnr
				fetchedMessage![0].ackTimestamp = Int32(packet.rxTime)
				
				if fetchedMessage![0].toUser != nil {
					fetchedMessage![0].toUser?.objectWillChange.send()
				} else {
					let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
					fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", connectedNodeNum)
					do {
						let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as? [MyInfoEntity]
						if fetchedMyInfo?.count ?? 0 > 0 {
							
							for ch in fetchedMyInfo![0].channels!.array as! [ChannelEntity] {
								
								if ch.index == packet.channel {
									ch.objectWillChange.send()
								}
							}
						}
					} catch {
						
					}
				}
				
			} else {
				return
			}
			try context.save()
			print("💾 ACK Saved for Message: \(packet.decoded.requestID)")
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving ACK for message: \(packet.id) Error: \(nsError)")
		}
	}
}

func telemetryPacket(packet: MeshPacket, connectedNode: Int64, context: NSManagedObjectContext) {
	
	if let telemetryMessage = try? Telemetry(serializedData: packet.decoded.payload) {
		
		// Only log telemetry from the mesh not the connected device
		if connectedNode != Int64(packet.from) {
			let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.telemetry.received %@", comment: "Telemetry received for: %@"), String(packet.from))
			MeshLogger.log("📈 \(logString)")
		}
		
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
			// Only log telemetry from the mesh not the connected device
			if connectedNode != Int64(packet.from) {
				print("💾 Telemetry Saved for Node: \(packet.from)")
			}
		} catch {
			context.rollback()
			let nsError = error as NSError
			print("💥 Error Saving Telemetry for Node \(packet.from) Error: \(nsError)")
		}
	} else {
		print("💥 Error Fetching NodeInfoEntity for Node \(packet.from)")
	}
}

func textMessageAppPacket(packet: MeshPacket, connectedNode: Int64, context: NSManagedObjectContext) {
	
	if let messageText = String(bytes: packet.decoded.payload, encoding: .utf8) {
		
		MeshLogger.log("💬 \(NSLocalizedString("mesh.log.textmessage.received", comment: "Message received from the text message app"))")
		
		let messageUsers: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "UserEntity")
		messageUsers.predicate = NSPredicate(format: "num IN %@", [packet.to, packet.from])
		
		do {
			
			let fetchedUsers = try context.fetch(messageUsers) as! [UserEntity]
			let newMessage = MessageEntity(context: context)
			newMessage.messageId = Int64(packet.id)
			newMessage.messageTimestamp = Int32(bitPattern: packet.rxTime)
			newMessage.receivedACK = false
			newMessage.snr = packet.rxSnr
			newMessage.isEmoji = packet.decoded.emoji == 1
			newMessage.channel = Int32(packet.channel)
			
			if packet.decoded.replyID > 0 {
				newMessage.replyID = Int64(packet.decoded.replyID)
			}
			
			if fetchedUsers.first(where: { $0.num == packet.to }) != nil && packet.to != 4294967295 {
				newMessage.toUser = fetchedUsers.first(where: { $0.num == packet.to })
			}
			if fetchedUsers.first(where: { $0.num == packet.from }) != nil {
				newMessage.fromUser = fetchedUsers.first(where: { $0.num == packet.from })
			}
			newMessage.messagePayload = messageText
			newMessage.messagePayloadMarkdown = generateMessageMarkdown(message: messageText)
			
			newMessage.fromUser?.objectWillChange.send()
			newMessage.toUser?.objectWillChange.send()
			
			var messageSaved = false
			
			do {
				
				try context.save()
				print("💾 Saved a new message for \(newMessage.messageId)")
				messageSaved = true
				
				if messageSaved {
					
					if newMessage.fromUser != nil && newMessage.toUser != nil && !(newMessage.fromUser?.mute ?? false) {
						// Create an iOS Notification for the received DM message and schedule it immediately
						let manager = LocalNotificationManager()
						manager.notifications = [
							Notification(
								id: ("notification.id.\(newMessage.messageId)"),
								title: "\(newMessage.fromUser?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))",
								subtitle: "AKA \(newMessage.fromUser?.shortName ?? "???")",
								content: messageText)
						]
						manager.schedule()
						print("💬 iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))")
					} else if newMessage.fromUser != nil && newMessage.toUser == nil {
						
						let fetchMyInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "MyInfoEntity")
						fetchMyInfoRequest.predicate = NSPredicate(format: "myNodeNum == %lld", Int64(connectedNode))
						
						do {
							let fetchedMyInfo = try context.fetch(fetchMyInfoRequest) as! [MyInfoEntity]
							for channel in (fetchedMyInfo[0].channels?.array ?? []) as? [ChannelEntity] ?? [] {
								if channel.index == newMessage.channel {
									context.refresh(channel, mergeChanges: true)
								}
								
								if channel.index == newMessage.channel && !channel.mute {
									// Create an iOS Notification for the received private channel message and schedule it immediately
									let manager = LocalNotificationManager()
									manager.notifications = [
										Notification(
											id: ("notification.id.\(newMessage.messageId)"),
											title: "\(newMessage.fromUser?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))",
											subtitle: "AKA \(newMessage.fromUser?.shortName ?? "???")",
											content: messageText)
									]
									manager.schedule()
									print("💬 iOS Notification Scheduled for text message from \(newMessage.fromUser?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))")
								}
							}
						} catch {
							
						}
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

func waypointPacket (packet: MeshPacket, context: NSManagedObjectContext) {
	
	let logString = String.localizedStringWithFormat(NSLocalizedString("mesh.log.waypoint.received %@", comment: "Waypoint Packet received from node: %@"), String(packet.from))
	MeshLogger.log("📍 \(logString)")
	
	let fetchWaypointRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "WaypointEntity")
	fetchWaypointRequest.predicate = NSPredicate(format: "id == %lld", Int64(packet.id))
	
	do {
		
		if let waypointMessage = try? Waypoint(serializedData: packet.decoded.payload) {

			let fetchedWaypoint = try context.fetch(fetchWaypointRequest) as! [WaypointEntity]
			if fetchedWaypoint.isEmpty {
				let waypoint = WaypointEntity(context: context)
				
				waypoint.id = Int64(packet.id)
				waypoint.name = waypointMessage.name
				waypoint.longDescription = waypointMessage.description_p
				waypoint.latitudeI = waypointMessage.latitudeI
				waypoint.longitudeI = waypointMessage.longitudeI
				waypoint.icon = Int64(waypointMessage.icon)
				waypoint.locked = Int64(waypointMessage.lockedTo)
				if waypointMessage.expire > 0 {
					waypoint.expire = Date(timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire)))
				}
				do {
					try context.save()
					print("💾 Updated Node Waypoint App Packet For: \(waypoint.id)")
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Saving WaypointEntity from WAYPOINT_APP \(nsError)")
				}
			} else {
				fetchedWaypoint[0].id = Int64(packet.id)
				fetchedWaypoint[0].name = waypointMessage.name
				fetchedWaypoint[0].longDescription = waypointMessage.description_p
				fetchedWaypoint[0].latitudeI = waypointMessage.latitudeI
				fetchedWaypoint[0].longitudeI = waypointMessage.longitudeI
				fetchedWaypoint[0].icon = Int64(waypointMessage.icon)
				fetchedWaypoint[0].locked = Int64(waypointMessage.lockedTo)
				if waypointMessage.expire > 0 {
					fetchedWaypoint[0].expire = Date(timeIntervalSince1970: TimeInterval(Int64(waypointMessage.expire)))
				}
				do {
					try context.save()
					print("💾 Updated Node Waypoint App Packet For: \(fetchedWaypoint[0].id)")
				} catch {
					context.rollback()
					let nsError = error as NSError
					print("💥 Error Saving WaypointEntity from WAYPOINT_APP \(nsError)")
				}
			}
		}
	} catch {
		print("💥 Error Deserializing WAYPOINT_APP packet.")
	}
}
