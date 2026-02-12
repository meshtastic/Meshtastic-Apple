//
//  ManagedAttributePropertyWrapper.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/26/24.
//
import CoreData

@propertyWrapper
public struct ManagedAttribute<Value: Numeric> {
	private let attributeName: String
	private let converter: (NSNumber) -> Value?

	public init(attributeName: String) {
		self.attributeName = attributeName

		// Define the converter closure based on the generic type Value
		if Value.self == Float.self {
			converter = { $0.floatValue as? Value }
		} else if Value.self == Double.self {
			converter = { $0.doubleValue as? Value }
		} else if Value.self == Int.self {
			converter = { $0.intValue as? Value }
		} else if Value.self == Int8.self {
			converter = { $0.int8Value as? Value }
		} else if Value.self == Int16.self {
			converter = { $0.int16Value as? Value }
		} else if Value.self == Int32.self {
			converter = { $0.int32Value as? Value }
		} else if Value.self == Int64.self {
			converter = { $0.int64Value as? Value }
		} else if Value.self == UInt32.self {
			converter = { $0.uint32Value as? Value }
		} else {
			fatalError("Unsupported type: \(Value.self)")
		}
	}

	public var wrappedValue: Value? {
		get { fatalError("Access via enclosing instance required.") }
		set { fatalError("Access via enclosing instance required.") }
	}

	public static subscript<EnclosingSelf: NSManagedObject>(
		_enclosingInstance observed: EnclosingSelf,
		wrapped wrappedKeyPath: KeyPath<EnclosingSelf, Value?>,
		storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, ManagedAttribute<Value>>
	) -> Value? {
		get {
			let wrapper = observed[keyPath: storageKeyPath]
			let number = observed.primitiveValue(forKey: wrapper.attributeName) as? NSNumber
			return number.flatMap { wrapper.converter($0) }
		}
		set {
			let wrapper = observed[keyPath: storageKeyPath]
			if let newValue = newValue {
				let number: NSNumber
				if let v = newValue as? Float {
					number = NSNumber(value: v)
				} else if let v = newValue as? Double {
					number = NSNumber(value: v)
				} else if let v = newValue as? Int {
					number = NSNumber(value: v)
				} else if let v = newValue as? Int8 {
					number = NSNumber(value: v)
				} else if let v = newValue as? Int16 {
					number = NSNumber(value: v)
				} else if let v = newValue as? Int32 {
					number = NSNumber(value: v)
				} else if let v = newValue as? Int64 {
					number = NSNumber(value: v)
				} else if let v = newValue as? UInt32 {
					number = NSNumber(value: v)
				} else {
					fatalError("Unsupported type: \(Value.self)")
				}
				observed.setPrimitiveValue(number, forKey: wrapper.attributeName)
			} else {
				observed.setPrimitiveValue(nil, forKey: wrapper.attributeName)
			}
		}
	}
}
