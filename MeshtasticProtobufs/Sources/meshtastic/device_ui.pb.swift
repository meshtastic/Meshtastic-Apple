// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: meshtastic/device_ui.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

public enum Theme: SwiftProtobuf.Enum, Swift.CaseIterable {
  public typealias RawValue = Int

  ///
  /// Dark
  case dark // = 0

  ///
  /// Light
  case light // = 1

  ///
  /// Red
  case red // = 2
  case UNRECOGNIZED(Int)

  public init() {
    self = .dark
  }

  public init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .dark
    case 1: self = .light
    case 2: self = .red
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  public var rawValue: Int {
    switch self {
    case .dark: return 0
    case .light: return 1
    case .red: return 2
    case .UNRECOGNIZED(let i): return i
    }
  }

  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static let allCases: [Theme] = [
    .dark,
    .light,
    .red,
  ]

}

///
/// Localization
public enum Language: SwiftProtobuf.Enum, Swift.CaseIterable {
  public typealias RawValue = Int

  ///
  /// English
  case english // = 0

  ///
  /// French
  case french // = 1

  ///
  /// German
  case german // = 2

  ///
  /// Italian
  case italian // = 3

  ///
  /// Portuguese
  case portuguese // = 4

  ///
  /// Spanish
  case spanish // = 5

  ///
  /// Swedish
  case swedish // = 6

  ///
  /// Finnish
  case finnish // = 7

  ///
  /// Polish
  case polish // = 8

  ///
  /// Turkish
  case turkish // = 9

  ///
  /// Serbian
  case serbian // = 10

  ///
  /// Russian
  case russian // = 11

  ///
  /// Dutch
  case dutch // = 12

  ///
  /// Greek
  case greek // = 13

  ///
  /// Norwegian
  case norwegian // = 14

  ///
  /// Simplified Chinese (experimental)
  case simplifiedChinese // = 30

  ///
  /// Traditional Chinese (experimental)
  case traditionalChinese // = 31
  case UNRECOGNIZED(Int)

  public init() {
    self = .english
  }

  public init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .english
    case 1: self = .french
    case 2: self = .german
    case 3: self = .italian
    case 4: self = .portuguese
    case 5: self = .spanish
    case 6: self = .swedish
    case 7: self = .finnish
    case 8: self = .polish
    case 9: self = .turkish
    case 10: self = .serbian
    case 11: self = .russian
    case 12: self = .dutch
    case 13: self = .greek
    case 14: self = .norwegian
    case 30: self = .simplifiedChinese
    case 31: self = .traditionalChinese
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  public var rawValue: Int {
    switch self {
    case .english: return 0
    case .french: return 1
    case .german: return 2
    case .italian: return 3
    case .portuguese: return 4
    case .spanish: return 5
    case .swedish: return 6
    case .finnish: return 7
    case .polish: return 8
    case .turkish: return 9
    case .serbian: return 10
    case .russian: return 11
    case .dutch: return 12
    case .greek: return 13
    case .norwegian: return 14
    case .simplifiedChinese: return 30
    case .traditionalChinese: return 31
    case .UNRECOGNIZED(let i): return i
    }
  }

  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static let allCases: [Language] = [
    .english,
    .french,
    .german,
    .italian,
    .portuguese,
    .spanish,
    .swedish,
    .finnish,
    .polish,
    .turkish,
    .serbian,
    .russian,
    .dutch,
    .greek,
    .norwegian,
    .simplifiedChinese,
    .traditionalChinese,
  ]

}

public struct DeviceUIConfig: @unchecked Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  ///
  /// A version integer used to invalidate saved files when we make incompatible changes.
  public var version: UInt32 {
    get {return _storage._version}
    set {_uniqueStorage()._version = newValue}
  }

  ///
  /// TFT display brightness 1..255 
  public var screenBrightness: UInt32 {
    get {return _storage._screenBrightness}
    set {_uniqueStorage()._screenBrightness = newValue}
  }

  ///
  /// Screen timeout 0..900 
  public var screenTimeout: UInt32 {
    get {return _storage._screenTimeout}
    set {_uniqueStorage()._screenTimeout = newValue}
  }

  ///
  /// Screen/Settings lock enabled 
  public var screenLock: Bool {
    get {return _storage._screenLock}
    set {_uniqueStorage()._screenLock = newValue}
  }

  public var settingsLock: Bool {
    get {return _storage._settingsLock}
    set {_uniqueStorage()._settingsLock = newValue}
  }

  public var pinCode: UInt32 {
    get {return _storage._pinCode}
    set {_uniqueStorage()._pinCode = newValue}
  }

  ///
  /// Color theme 
  public var theme: Theme {
    get {return _storage._theme}
    set {_uniqueStorage()._theme = newValue}
  }

  ///
  /// Audible message, banner and ring tone
  public var alertEnabled: Bool {
    get {return _storage._alertEnabled}
    set {_uniqueStorage()._alertEnabled = newValue}
  }

  public var bannerEnabled: Bool {
    get {return _storage._bannerEnabled}
    set {_uniqueStorage()._bannerEnabled = newValue}
  }

  public var ringToneID: UInt32 {
    get {return _storage._ringToneID}
    set {_uniqueStorage()._ringToneID = newValue}
  }

  ///
  /// Localization 
  public var language: Language {
    get {return _storage._language}
    set {_uniqueStorage()._language = newValue}
  }

  ///
  /// Node list filter 
  public var nodeFilter: NodeFilter {
    get {return _storage._nodeFilter ?? NodeFilter()}
    set {_uniqueStorage()._nodeFilter = newValue}
  }
  /// Returns true if `nodeFilter` has been explicitly set.
  public var hasNodeFilter: Bool {return _storage._nodeFilter != nil}
  /// Clears the value of `nodeFilter`. Subsequent reads from it will return its default value.
  public mutating func clearNodeFilter() {_uniqueStorage()._nodeFilter = nil}

  ///
  /// Node list highlightening
  public var nodeHighlight: NodeHighlight {
    get {return _storage._nodeHighlight ?? NodeHighlight()}
    set {_uniqueStorage()._nodeHighlight = newValue}
  }
  /// Returns true if `nodeHighlight` has been explicitly set.
  public var hasNodeHighlight: Bool {return _storage._nodeHighlight != nil}
  /// Clears the value of `nodeHighlight`. Subsequent reads from it will return its default value.
  public mutating func clearNodeHighlight() {_uniqueStorage()._nodeHighlight = nil}

  ///
  /// 8 integers for screen calibration data
  public var calibrationData: Data {
    get {return _storage._calibrationData}
    set {_uniqueStorage()._calibrationData = newValue}
  }

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

public struct NodeFilter: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  ///
  /// Filter unknown nodes
  public var unknownSwitch: Bool = false

  ///
  /// Filter offline nodes
  public var offlineSwitch: Bool = false

  ///
  /// Filter nodes w/o public key
  public var publicKeySwitch: Bool = false

  ///
  /// Filter based on hops away
  public var hopsAway: Int32 = 0

  ///
  /// Filter nodes w/o position
  public var positionSwitch: Bool = false

  ///
  /// Filter nodes by matching name string
  public var nodeName: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

public struct NodeHighlight: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  ///
  /// Hightlight nodes w/ active chat
  public var chatSwitch: Bool = false

  ///
  /// Highlight nodes w/ position
  public var positionSwitch: Bool = false

  ///
  /// Highlight nodes w/ telemetry data
  public var telemetrySwitch: Bool = false

  ///
  /// Highlight nodes w/ iaq data
  public var iaqSwitch: Bool = false

  ///
  /// Highlight nodes by matching name string
  public var nodeName: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "meshtastic"

extension Theme: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "DARK"),
    1: .same(proto: "LIGHT"),
    2: .same(proto: "RED"),
  ]
}

extension Language: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "ENGLISH"),
    1: .same(proto: "FRENCH"),
    2: .same(proto: "GERMAN"),
    3: .same(proto: "ITALIAN"),
    4: .same(proto: "PORTUGUESE"),
    5: .same(proto: "SPANISH"),
    6: .same(proto: "SWEDISH"),
    7: .same(proto: "FINNISH"),
    8: .same(proto: "POLISH"),
    9: .same(proto: "TURKISH"),
    10: .same(proto: "SERBIAN"),
    11: .same(proto: "RUSSIAN"),
    12: .same(proto: "DUTCH"),
    13: .same(proto: "GREEK"),
    14: .same(proto: "NORWEGIAN"),
    30: .same(proto: "SIMPLIFIED_CHINESE"),
    31: .same(proto: "TRADITIONAL_CHINESE"),
  ]
}

extension DeviceUIConfig: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".DeviceUIConfig"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "version"),
    2: .standard(proto: "screen_brightness"),
    3: .standard(proto: "screen_timeout"),
    4: .standard(proto: "screen_lock"),
    5: .standard(proto: "settings_lock"),
    6: .standard(proto: "pin_code"),
    7: .same(proto: "theme"),
    8: .standard(proto: "alert_enabled"),
    9: .standard(proto: "banner_enabled"),
    10: .standard(proto: "ring_tone_id"),
    11: .same(proto: "language"),
    12: .standard(proto: "node_filter"),
    13: .standard(proto: "node_highlight"),
    14: .standard(proto: "calibration_data"),
  ]

  fileprivate class _StorageClass {
    var _version: UInt32 = 0
    var _screenBrightness: UInt32 = 0
    var _screenTimeout: UInt32 = 0
    var _screenLock: Bool = false
    var _settingsLock: Bool = false
    var _pinCode: UInt32 = 0
    var _theme: Theme = .dark
    var _alertEnabled: Bool = false
    var _bannerEnabled: Bool = false
    var _ringToneID: UInt32 = 0
    var _language: Language = .english
    var _nodeFilter: NodeFilter? = nil
    var _nodeHighlight: NodeHighlight? = nil
    var _calibrationData: Data = Data()

    #if swift(>=5.10)
      // This property is used as the initial default value for new instances of the type.
      // The type itself is protecting the reference to its storage via CoW semantics.
      // This will force a copy to be made of this reference when the first mutation occurs;
      // hence, it is safe to mark this as `nonisolated(unsafe)`.
      static nonisolated(unsafe) let defaultInstance = _StorageClass()
    #else
      static let defaultInstance = _StorageClass()
    #endif

    private init() {}

    init(copying source: _StorageClass) {
      _version = source._version
      _screenBrightness = source._screenBrightness
      _screenTimeout = source._screenTimeout
      _screenLock = source._screenLock
      _settingsLock = source._settingsLock
      _pinCode = source._pinCode
      _theme = source._theme
      _alertEnabled = source._alertEnabled
      _bannerEnabled = source._bannerEnabled
      _ringToneID = source._ringToneID
      _language = source._language
      _nodeFilter = source._nodeFilter
      _nodeHighlight = source._nodeHighlight
      _calibrationData = source._calibrationData
    }
  }

  fileprivate mutating func _uniqueStorage() -> _StorageClass {
    if !isKnownUniquelyReferenced(&_storage) {
      _storage = _StorageClass(copying: _storage)
    }
    return _storage
  }

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    _ = _uniqueStorage()
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      while let fieldNumber = try decoder.nextFieldNumber() {
        // The use of inline closures is to circumvent an issue where the compiler
        // allocates stack space for every case branch when no optimizations are
        // enabled. https://github.com/apple/swift-protobuf/issues/1034
        switch fieldNumber {
        case 1: try { try decoder.decodeSingularUInt32Field(value: &_storage._version) }()
        case 2: try { try decoder.decodeSingularUInt32Field(value: &_storage._screenBrightness) }()
        case 3: try { try decoder.decodeSingularUInt32Field(value: &_storage._screenTimeout) }()
        case 4: try { try decoder.decodeSingularBoolField(value: &_storage._screenLock) }()
        case 5: try { try decoder.decodeSingularBoolField(value: &_storage._settingsLock) }()
        case 6: try { try decoder.decodeSingularUInt32Field(value: &_storage._pinCode) }()
        case 7: try { try decoder.decodeSingularEnumField(value: &_storage._theme) }()
        case 8: try { try decoder.decodeSingularBoolField(value: &_storage._alertEnabled) }()
        case 9: try { try decoder.decodeSingularBoolField(value: &_storage._bannerEnabled) }()
        case 10: try { try decoder.decodeSingularUInt32Field(value: &_storage._ringToneID) }()
        case 11: try { try decoder.decodeSingularEnumField(value: &_storage._language) }()
        case 12: try { try decoder.decodeSingularMessageField(value: &_storage._nodeFilter) }()
        case 13: try { try decoder.decodeSingularMessageField(value: &_storage._nodeHighlight) }()
        case 14: try { try decoder.decodeSingularBytesField(value: &_storage._calibrationData) }()
        default: break
        }
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every if/case branch local when no optimizations
      // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
      // https://github.com/apple/swift-protobuf/issues/1182
      if _storage._version != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._version, fieldNumber: 1)
      }
      if _storage._screenBrightness != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._screenBrightness, fieldNumber: 2)
      }
      if _storage._screenTimeout != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._screenTimeout, fieldNumber: 3)
      }
      if _storage._screenLock != false {
        try visitor.visitSingularBoolField(value: _storage._screenLock, fieldNumber: 4)
      }
      if _storage._settingsLock != false {
        try visitor.visitSingularBoolField(value: _storage._settingsLock, fieldNumber: 5)
      }
      if _storage._pinCode != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._pinCode, fieldNumber: 6)
      }
      if _storage._theme != .dark {
        try visitor.visitSingularEnumField(value: _storage._theme, fieldNumber: 7)
      }
      if _storage._alertEnabled != false {
        try visitor.visitSingularBoolField(value: _storage._alertEnabled, fieldNumber: 8)
      }
      if _storage._bannerEnabled != false {
        try visitor.visitSingularBoolField(value: _storage._bannerEnabled, fieldNumber: 9)
      }
      if _storage._ringToneID != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._ringToneID, fieldNumber: 10)
      }
      if _storage._language != .english {
        try visitor.visitSingularEnumField(value: _storage._language, fieldNumber: 11)
      }
      try { if let v = _storage._nodeFilter {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 12)
      } }()
      try { if let v = _storage._nodeHighlight {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 13)
      } }()
      if !_storage._calibrationData.isEmpty {
        try visitor.visitSingularBytesField(value: _storage._calibrationData, fieldNumber: 14)
      }
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: DeviceUIConfig, rhs: DeviceUIConfig) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._version != rhs_storage._version {return false}
        if _storage._screenBrightness != rhs_storage._screenBrightness {return false}
        if _storage._screenTimeout != rhs_storage._screenTimeout {return false}
        if _storage._screenLock != rhs_storage._screenLock {return false}
        if _storage._settingsLock != rhs_storage._settingsLock {return false}
        if _storage._pinCode != rhs_storage._pinCode {return false}
        if _storage._theme != rhs_storage._theme {return false}
        if _storage._alertEnabled != rhs_storage._alertEnabled {return false}
        if _storage._bannerEnabled != rhs_storage._bannerEnabled {return false}
        if _storage._ringToneID != rhs_storage._ringToneID {return false}
        if _storage._language != rhs_storage._language {return false}
        if _storage._nodeFilter != rhs_storage._nodeFilter {return false}
        if _storage._nodeHighlight != rhs_storage._nodeHighlight {return false}
        if _storage._calibrationData != rhs_storage._calibrationData {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension NodeFilter: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".NodeFilter"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "unknown_switch"),
    2: .standard(proto: "offline_switch"),
    3: .standard(proto: "public_key_switch"),
    4: .standard(proto: "hops_away"),
    5: .standard(proto: "position_switch"),
    6: .standard(proto: "node_name"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.unknownSwitch) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self.offlineSwitch) }()
      case 3: try { try decoder.decodeSingularBoolField(value: &self.publicKeySwitch) }()
      case 4: try { try decoder.decodeSingularInt32Field(value: &self.hopsAway) }()
      case 5: try { try decoder.decodeSingularBoolField(value: &self.positionSwitch) }()
      case 6: try { try decoder.decodeSingularStringField(value: &self.nodeName) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.unknownSwitch != false {
      try visitor.visitSingularBoolField(value: self.unknownSwitch, fieldNumber: 1)
    }
    if self.offlineSwitch != false {
      try visitor.visitSingularBoolField(value: self.offlineSwitch, fieldNumber: 2)
    }
    if self.publicKeySwitch != false {
      try visitor.visitSingularBoolField(value: self.publicKeySwitch, fieldNumber: 3)
    }
    if self.hopsAway != 0 {
      try visitor.visitSingularInt32Field(value: self.hopsAway, fieldNumber: 4)
    }
    if self.positionSwitch != false {
      try visitor.visitSingularBoolField(value: self.positionSwitch, fieldNumber: 5)
    }
    if !self.nodeName.isEmpty {
      try visitor.visitSingularStringField(value: self.nodeName, fieldNumber: 6)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: NodeFilter, rhs: NodeFilter) -> Bool {
    if lhs.unknownSwitch != rhs.unknownSwitch {return false}
    if lhs.offlineSwitch != rhs.offlineSwitch {return false}
    if lhs.publicKeySwitch != rhs.publicKeySwitch {return false}
    if lhs.hopsAway != rhs.hopsAway {return false}
    if lhs.positionSwitch != rhs.positionSwitch {return false}
    if lhs.nodeName != rhs.nodeName {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension NodeHighlight: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".NodeHighlight"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "chat_switch"),
    2: .standard(proto: "position_switch"),
    3: .standard(proto: "telemetry_switch"),
    4: .standard(proto: "iaq_switch"),
    5: .standard(proto: "node_name"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.chatSwitch) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self.positionSwitch) }()
      case 3: try { try decoder.decodeSingularBoolField(value: &self.telemetrySwitch) }()
      case 4: try { try decoder.decodeSingularBoolField(value: &self.iaqSwitch) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self.nodeName) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.chatSwitch != false {
      try visitor.visitSingularBoolField(value: self.chatSwitch, fieldNumber: 1)
    }
    if self.positionSwitch != false {
      try visitor.visitSingularBoolField(value: self.positionSwitch, fieldNumber: 2)
    }
    if self.telemetrySwitch != false {
      try visitor.visitSingularBoolField(value: self.telemetrySwitch, fieldNumber: 3)
    }
    if self.iaqSwitch != false {
      try visitor.visitSingularBoolField(value: self.iaqSwitch, fieldNumber: 4)
    }
    if !self.nodeName.isEmpty {
      try visitor.visitSingularStringField(value: self.nodeName, fieldNumber: 5)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: NodeHighlight, rhs: NodeHighlight) -> Bool {
    if lhs.chatSwitch != rhs.chatSwitch {return false}
    if lhs.positionSwitch != rhs.positionSwitch {return false}
    if lhs.telemetrySwitch != rhs.telemetrySwitch {return false}
    if lhs.iaqSwitch != rhs.iaqSwitch {return false}
    if lhs.nodeName != rhs.nodeName {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
