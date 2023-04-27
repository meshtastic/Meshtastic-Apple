//
//  HardwareModels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 3/11/23.
//

import Foundation

enum HardwareModels: String, CaseIterable, Identifiable {

	case UNSET
	case TLORAV2
	case TLORAV1
	case TLORAV211P6
	case TBEAM
	case HELTECV20
	case TBEAMV0P7
	case TECHO
	case TLORAV11P3
	case RAK4631
	case HELTECV21
	case HELTECV1
	case DIYV1
	case LILYGOTBEAMS3CORE
	case RAK11200
	case NANOG1
	case TLORAV211P8
	case TLORAT3S3
	case NANOG1EXPLORER
	case STATIONG1
	case M5STACK
	case HELTECV3
	case HELTECWSLV3

	var id: String { self.rawValue }
	var description: String {
		switch self {

		case .UNSET:
			return NSLocalizedString("unset", comment: "UNSET")
		case .TLORAV2:
			return "TLoRa V2"
		case .TLORAV1:
			return "TLoRa V1"
		case .TLORAV211P6:
			return "TLoRa V2.1.1.6"
		case .TBEAM:
			return "TBeam"
		case .HELTECV20:
			return "HELTEC V2.0"
		case .TBEAMV0P7:
			return "TBeam 0.7"
		case .TECHO:
			return "TEcho"
		case .TLORAV11P3:
			return "TLORA V1.1.3"
		case .RAK4631:
			return "RAK 4631 NRF"
		case .HELTECV21:
			return "HELTEC V2.1"
		case .HELTECV1:
			return "HELTEC V1"
		case .DIYV1:
			return "Hydra 1W DIY"
		case .LILYGOTBEAMS3CORE:
			return "TBEAM S3"
		case .RAK11200:
			return "RAK 11200 ESP32"
		case .NANOG1:
			return "Nano G1"
		case .TLORAV211P8:
			return "TLoRa V2.1.1.8"
		case .TLORAT3S3:
			return "TLoRa T3 S3"
		case .NANOG1EXPLORER:
			return "Nano G1 Explorer"
		case .STATIONG1:
			return "Station G1"
		case .M5STACK:
			return "M5 Stack"
		case .HELTECV3:
			return "Heltec V3"
		case .HELTECWSLV3:
			return "Heltec wireless stick lite V3"
		}

	}
	var firmwareStrings: [String] {
		switch self {

		case .UNSET:
			return []
		case .TLORAV2:
			return ["firmware-tlora-v2-"]
		case .TLORAV1:
			return ["firmware-tlora-v1-"]
		case .TLORAV211P6:
			return ["firmware-tlora-v2-1-1.6-"]
		case .TBEAM:
			return ["firmware-tbeam-"]
		case .HELTECV20:
			return ["firmware-heltec-v2.0-"]
		case .TBEAMV0P7:
			return ["firmware-tbeam0.7-"]
		case .TECHO:
			return ["firmware-t-echo-"]
		case .TLORAV11P3:
			return ["firmware-tlora_v1_3-"]
		case .RAK4631:
			return ["firmware-rak4631-", "firmware-rak4631_eink-"]
		case .HELTECV21:
			return ["firmware-heltec-v2.1-"]
		case .HELTECV1:
			return ["firmware-heltec-v1-"]
		case .DIYV1:
			return ["firmware-meshtastic-diy-v1"]
		case .LILYGOTBEAMS3CORE:
			return ["firmware-tbeam-s3-core-"]
		case .RAK11200:
			return ["firmware-rak11200-"]
		case .NANOG1:
			return ["firmware-nano-g1-"]
		case .TLORAV211P8:
			return ["firmware-tlora-v2-1-1.8-"]
		case .TLORAT3S3:
			return ["firmware-tlora-t3s3-v1-"]
		case .NANOG1EXPLORER:
			return ["firmware-nano-g1-explorer-"]
		case .STATIONG1:
			return ["firmware-station-g1-"]
		case .M5STACK:
			return ["firmware-m5stack-core-", "firmware-m5stack-coreink-"]
		case .HELTECV3:
			return ["firmware-heltec-v3-"]
		case .HELTECWSLV3:
			return ["firmware-heltec-wsl-v3-"]
		}

	}
	func platform() -> HardwarePlatforms {

		switch self {

		case .UNSET:
			return HardwarePlatforms.none
		case .TLORAV2:
			return HardwarePlatforms.esp32
		case .TLORAV1:
			return HardwarePlatforms.esp32
		case .TLORAV211P6:
			return HardwarePlatforms.esp32
		case .TBEAM:
			return HardwarePlatforms.esp32
		case .HELTECV20:
			return HardwarePlatforms.esp32
		case .TBEAMV0P7:
			return HardwarePlatforms.esp32
		case .TECHO:
			return HardwarePlatforms.nrf52
		case .TLORAV11P3:
			return HardwarePlatforms.esp32
		case .RAK4631:
			return HardwarePlatforms.nrf52
		case .HELTECV21:
			return HardwarePlatforms.esp32
		case .HELTECV1:
			return HardwarePlatforms.esp32
		case .DIYV1:
			return HardwarePlatforms.esp32
		case .LILYGOTBEAMS3CORE:
			return HardwarePlatforms.esp32
		case .RAK11200:
			return HardwarePlatforms.esp32
		case .NANOG1:
			return HardwarePlatforms.esp32
		case .TLORAV211P8:
			return HardwarePlatforms.esp32
		case .TLORAT3S3:
			return HardwarePlatforms.esp32
		case .NANOG1EXPLORER:
			return HardwarePlatforms.esp32
		case .STATIONG1:
			return HardwarePlatforms.esp32
		case .M5STACK:
			return HardwarePlatforms.esp32
		case .HELTECV3:
			return HardwarePlatforms.esp32
		case .HELTECWSLV3:
			return HardwarePlatforms.esp32
		}
	}
	func protoEnumValue() -> HardwareModel {

		switch self {

		case .UNSET:
			return HardwareModel.unset
		case .TLORAV2:
			return HardwareModel.tloraV2
		case .TLORAV1:
			return HardwareModel.tloraV1
		case .TLORAV211P6:
			return HardwareModel.tloraV211P6
		case .TBEAM:
			return HardwareModel.tbeam
		case .HELTECV20:
			return HardwareModel.heltecV20
		case .TBEAMV0P7:
			return HardwareModel.tbeamV0P7
		case .TECHO:
			return HardwareModel.tEcho
		case .TLORAV11P3:
			return HardwareModel.tloraV11P3
		case .RAK4631:
			return HardwareModel.rak4631
		case .HELTECV21:
			return HardwareModel.heltecV21
		case .HELTECV1:
			return HardwareModel.heltecV1
		case .DIYV1:
			return HardwareModel.diyV1
		case .LILYGOTBEAMS3CORE:
			return HardwareModel.lilygoTbeamS3Core
		case .RAK11200:
			return HardwareModel.rak11200
		case .NANOG1:
			return HardwareModel.nanoG1
		case .TLORAV211P8:
			return HardwareModel.tloraV211P8
		case .TLORAT3S3:
			return HardwareModel.tloraT3S3
		case .NANOG1EXPLORER:
			return HardwareModel.nanoG1Explorer
		case .STATIONG1:
			return HardwareModel.stationG1
		case .M5STACK:
			return HardwareModel.m5Stack
		case .HELTECV3:
			return HardwareModel.heltecV3
		case .HELTECWSLV3:
			return HardwareModel.heltecWslV3
		}
	}
}


enum HardwarePlatforms: String, CaseIterable, Identifiable {
	
	case none
	case esp32
	case nrf52
	case stm32
	case piPico
	case linux
	var id: String { self.rawValue }
	var description: String {
		switch self {
			
		case .none:
			return "None"
		case .esp32:
			return "Expressif ESP 32"
		case .nrf52:
			return "Nordic NRF52"
		case .stm32:
			return "ARM STM 32"
		case .piPico:
			return "Raspberrry Pi Pico"
		case .linux:
			return "Linux"
		}
	}
}
