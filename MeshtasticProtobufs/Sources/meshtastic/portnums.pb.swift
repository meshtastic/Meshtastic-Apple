// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: meshtastic/portnums.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

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

///
/// For any new 'apps' that run on the device or via sister apps on phones/PCs they should pick and use a
/// unique 'portnum' for their application.
/// If you are making a new app using meshtastic, please send in a pull request to add your 'portnum' to this
/// master table.
/// PortNums should be assigned in the following range:
/// 0-63   Core Meshtastic use, do not use for third party apps
/// 64-127 Registered 3rd party apps, send in a pull request that adds a new entry to portnums.proto to  register your application
/// 256-511 Use one of these portnums for your private applications that you don't want to register publically
/// All other values are reserved.
/// Note: This was formerly a Type enum named 'typ' with the same id #
/// We have change to this 'portnum' based scheme for specifying app handlers for particular payloads.
/// This change is backwards compatible by treating the legacy OPAQUE/CLEAR_TEXT values identically.
public enum PortNum: SwiftProtobuf.Enum, Swift.CaseIterable {
  public typealias RawValue = Int

  ///
  /// Deprecated: do not use in new code (formerly called OPAQUE)
  /// A message sent from a device outside of the mesh, in a form the mesh does not understand
  /// NOTE: This must be 0, because it is documented in IMeshService.aidl to be so
  /// ENCODING: binary undefined
  case unknownApp // = 0

  ///
  /// A simple UTF-8 text message, which even the little micros in the mesh
  /// can understand and show on their screen eventually in some circumstances
  /// even signal might send messages in this form (see below)
  /// ENCODING: UTF-8 Plaintext (?)
  case textMessageApp // = 1

  ///
  /// Reserved for built-in GPIO/example app.
  /// See remote_hardware.proto/HardwareMessage for details on the message sent/received to this port number
  /// ENCODING: Protobuf
  case remoteHardwareApp // = 2

  ///
  /// The built-in position messaging app.
  /// Payload is a Position message.
  /// ENCODING: Protobuf
  case positionApp // = 3

  ///
  /// The built-in user info app.
  /// Payload is a User message.
  /// ENCODING: Protobuf
  case nodeinfoApp // = 4

  ///
  /// Protocol control packets for mesh protocol use.
  /// Payload is a Routing message.
  /// ENCODING: Protobuf
  case routingApp // = 5

  ///
  /// Admin control packets.
  /// Payload is a AdminMessage message.
  /// ENCODING: Protobuf
  case adminApp // = 6

  ///
  /// Compressed TEXT_MESSAGE payloads.
  /// ENCODING: UTF-8 Plaintext (?) with Unishox2 Compression
  /// NOTE: The Device Firmware converts a TEXT_MESSAGE_APP to TEXT_MESSAGE_COMPRESSED_APP if the compressed
  /// payload is shorter. There's no need for app developers to do this themselves. Also the firmware will decompress
  /// any incoming TEXT_MESSAGE_COMPRESSED_APP payload and convert to TEXT_MESSAGE_APP.
  case textMessageCompressedApp // = 7

  ///
  /// Waypoint payloads.
  /// Payload is a Waypoint message.
  /// ENCODING: Protobuf
  case waypointApp // = 8

  ///
  /// Audio Payloads.
  /// Encapsulated codec2 packets. On 2.4 GHZ Bandwidths only for now
  /// ENCODING: codec2 audio frames
  /// NOTE: audio frames contain a 3 byte header (0xc0 0xde 0xc2) and a one byte marker for the decompressed bitrate.
  /// This marker comes from the 'moduleConfig.audio.bitrate' enum minus one.
  case audioApp // = 9

  ///
  /// Same as Text Message but originating from Detection Sensor Module.
  /// NOTE: This portnum traffic is not sent to the public MQTT starting at firmware version 2.2.9
  case detectionSensorApp // = 10

  ///
  /// Same as Text Message but used for critical alerts.
  case alertApp // = 11

  ///
  /// Provides a 'ping' service that replies to any packet it receives.
  /// Also serves as a small example module.
  /// ENCODING: ASCII Plaintext
  case replyApp // = 32

  ///
  /// Used for the python IP tunnel feature
  /// ENCODING: IP Packet. Handled by the python API, firmware ignores this one and pases on.
  case ipTunnelApp // = 33

  ///
  /// Paxcounter lib included in the firmware
  /// ENCODING: protobuf
  case paxcounterApp // = 34

  ///
  /// Provides a hardware serial interface to send and receive from the Meshtastic network.
  /// Connect to the RX/TX pins of a device with 38400 8N1. Packets received from the Meshtastic
  /// network is forwarded to the RX pin while sending a packet to TX will go out to the Mesh network.
  /// Maximum packet size of 240 bytes.
  /// Module is disabled by default can be turned on by setting SERIAL_MODULE_ENABLED = 1 in SerialPlugh.cpp.
  /// ENCODING: binary undefined
  case serialApp // = 64

  ///
  /// STORE_FORWARD_APP (Work in Progress)
  /// Maintained by Jm Casler (MC Hamster) : jm@casler.org
  /// ENCODING: Protobuf
  case storeForwardApp // = 65

  ///
  /// Optional port for messages for the range test module.
  /// ENCODING: ASCII Plaintext
  /// NOTE: This portnum traffic is not sent to the public MQTT starting at firmware version 2.2.9
  case rangeTestApp // = 66

  ///
  /// Provides a format to send and receive telemetry data from the Meshtastic network.
  /// Maintained by Charles Crossan (crossan007) : crossan007@gmail.com
  /// ENCODING: Protobuf
  case telemetryApp // = 67

  ///
  /// Experimental tools for estimating node position without a GPS
  /// Maintained by Github user a-f-G-U-C (a Meshtastic contributor)
  /// Project files at https://github.com/a-f-G-U-C/Meshtastic-ZPS
  /// ENCODING: arrays of int64 fields
  case zpsApp // = 68

  ///
  /// Used to let multiple instances of Linux native applications communicate
  /// as if they did using their LoRa chip.
  /// Maintained by GitHub user GUVWAF.
  /// Project files at https://github.com/GUVWAF/Meshtasticator
  /// ENCODING: Protobuf (?)
  case simulatorApp // = 69

  ///
  /// Provides a traceroute functionality to show the route a packet towards
  /// a certain destination would take on the mesh. Contains a RouteDiscovery message as payload.
  /// ENCODING: Protobuf
  case tracerouteApp // = 70

  ///
  /// Aggregates edge info for the network by sending out a list of each node's neighbors
  /// ENCODING: Protobuf
  case neighborinfoApp // = 71

  ///
  /// ATAK Plugin
  /// Portnum for payloads from the official Meshtastic ATAK plugin
  case atakPlugin // = 72

  ///
  /// Provides unencrypted information about a node for consumption by a map via MQTT
  case mapReportApp // = 73

  ///
  /// PowerStress based monitoring support (for automated power consumption testing)
  case powerstressApp // = 74

  ///
  /// Private applications should use portnums >= 256.
  /// To simplify initial development and testing you can use "PRIVATE_APP"
  /// in your code without needing to rebuild protobuf files (via [regen-protos.sh](https://github.com/meshtastic/firmware/blob/master/bin/regen-protos.sh))
  case privateApp // = 256

  ///
  /// ATAK Forwarder Module https://github.com/paulmandal/atak-forwarder
  /// ENCODING: libcotshrink
  case atakForwarder // = 257

  ///
  /// Currently we limit port nums to no higher than this value
  case max // = 511
  case UNRECOGNIZED(Int)

  public init() {
    self = .unknownApp
  }

  public init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownApp
    case 1: self = .textMessageApp
    case 2: self = .remoteHardwareApp
    case 3: self = .positionApp
    case 4: self = .nodeinfoApp
    case 5: self = .routingApp
    case 6: self = .adminApp
    case 7: self = .textMessageCompressedApp
    case 8: self = .waypointApp
    case 9: self = .audioApp
    case 10: self = .detectionSensorApp
    case 11: self = .alertApp
    case 32: self = .replyApp
    case 33: self = .ipTunnelApp
    case 34: self = .paxcounterApp
    case 64: self = .serialApp
    case 65: self = .storeForwardApp
    case 66: self = .rangeTestApp
    case 67: self = .telemetryApp
    case 68: self = .zpsApp
    case 69: self = .simulatorApp
    case 70: self = .tracerouteApp
    case 71: self = .neighborinfoApp
    case 72: self = .atakPlugin
    case 73: self = .mapReportApp
    case 74: self = .powerstressApp
    case 256: self = .privateApp
    case 257: self = .atakForwarder
    case 511: self = .max
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  public var rawValue: Int {
    switch self {
    case .unknownApp: return 0
    case .textMessageApp: return 1
    case .remoteHardwareApp: return 2
    case .positionApp: return 3
    case .nodeinfoApp: return 4
    case .routingApp: return 5
    case .adminApp: return 6
    case .textMessageCompressedApp: return 7
    case .waypointApp: return 8
    case .audioApp: return 9
    case .detectionSensorApp: return 10
    case .alertApp: return 11
    case .replyApp: return 32
    case .ipTunnelApp: return 33
    case .paxcounterApp: return 34
    case .serialApp: return 64
    case .storeForwardApp: return 65
    case .rangeTestApp: return 66
    case .telemetryApp: return 67
    case .zpsApp: return 68
    case .simulatorApp: return 69
    case .tracerouteApp: return 70
    case .neighborinfoApp: return 71
    case .atakPlugin: return 72
    case .mapReportApp: return 73
    case .powerstressApp: return 74
    case .privateApp: return 256
    case .atakForwarder: return 257
    case .max: return 511
    case .UNRECOGNIZED(let i): return i
    }
  }

  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static let allCases: [PortNum] = [
    .unknownApp,
    .textMessageApp,
    .remoteHardwareApp,
    .positionApp,
    .nodeinfoApp,
    .routingApp,
    .adminApp,
    .textMessageCompressedApp,
    .waypointApp,
    .audioApp,
    .detectionSensorApp,
    .alertApp,
    .replyApp,
    .ipTunnelApp,
    .paxcounterApp,
    .serialApp,
    .storeForwardApp,
    .rangeTestApp,
    .telemetryApp,
    .zpsApp,
    .simulatorApp,
    .tracerouteApp,
    .neighborinfoApp,
    .atakPlugin,
    .mapReportApp,
    .powerstressApp,
    .privateApp,
    .atakForwarder,
    .max,
  ]

}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension PortNum: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_APP"),
    1: .same(proto: "TEXT_MESSAGE_APP"),
    2: .same(proto: "REMOTE_HARDWARE_APP"),
    3: .same(proto: "POSITION_APP"),
    4: .same(proto: "NODEINFO_APP"),
    5: .same(proto: "ROUTING_APP"),
    6: .same(proto: "ADMIN_APP"),
    7: .same(proto: "TEXT_MESSAGE_COMPRESSED_APP"),
    8: .same(proto: "WAYPOINT_APP"),
    9: .same(proto: "AUDIO_APP"),
    10: .same(proto: "DETECTION_SENSOR_APP"),
    11: .same(proto: "ALERT_APP"),
    32: .same(proto: "REPLY_APP"),
    33: .same(proto: "IP_TUNNEL_APP"),
    34: .same(proto: "PAXCOUNTER_APP"),
    64: .same(proto: "SERIAL_APP"),
    65: .same(proto: "STORE_FORWARD_APP"),
    66: .same(proto: "RANGE_TEST_APP"),
    67: .same(proto: "TELEMETRY_APP"),
    68: .same(proto: "ZPS_APP"),
    69: .same(proto: "SIMULATOR_APP"),
    70: .same(proto: "TRACEROUTE_APP"),
    71: .same(proto: "NEIGHBORINFO_APP"),
    72: .same(proto: "ATAK_PLUGIN"),
    73: .same(proto: "MAP_REPORT_APP"),
    74: .same(proto: "POWERSTRESS_APP"),
    256: .same(proto: "PRIVATE_APP"),
    257: .same(proto: "ATAK_FORWARDER"),
    511: .same(proto: "MAX"),
  ]
}
