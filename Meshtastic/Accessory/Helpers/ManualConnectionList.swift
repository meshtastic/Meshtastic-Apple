//
//  ManualConnectionList.swift
//  Meshtastic
//
//  Created by jake on 10/26/25.
//

import Foundation

// Maintains an observable list of devices that's backed by UserDefaults
public class ManualConnectionList: ObservableObject {
	static let shared = ManualConnectionList()
	
	@Published private var _list: [Device]
	
	private init() {
		_list = UserDefaults.manualConnections
	}
	
	var connectionsList: [Device] {
		get {
			return _list
		}
	}
	
	func insert(device: Device) {
		// Don't insert if already there
		guard !_list.contains(where: {$0.id == device.id}) else {
			return
		}
		
		// Add the new entry
		var list = _list
		list.append(device)
		_list = list
		UserDefaults.manualConnections = list
	}
	
	func updateDevice<T>(deviceId: UUID, key: WritableKeyPath<Device, T>, value: T) where T: Equatable {
		var list = _list
		if let deviceIndex = list.firstIndex(where: {$0.id == deviceId}) {
			list[deviceIndex][keyPath: key] = value
			_list = list
			UserDefaults.manualConnections = list
		}		
	}
	
	func remove(device: Device) {
		var list = _list
		list.removeAll(where: {$0.id == device.id})
		_list = list
		UserDefaults.manualConnections = list
	}
	
	func remove(atOffsets: IndexSet) {
		var list = _list
		list.remove(atOffsets: atOffsets)
		_list = list
		UserDefaults.manualConnections = list
	}
}
