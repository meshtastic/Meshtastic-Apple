//
//  ModemPresets.swift
//  Meshtastic
//

import Foundation
import MeshtasticProtobufs

enum ModemPresets: Int, CaseIterable, Identifiable {

    case longFast = 0
    case longSlow = 1
    case longModerate = 7
    case longTurbo = 9
    case medSlow = 3
    case medFast = 4
    case shortSlow = 5
    case shortFast = 6
    case shortTurbo = 8
    case liteFast = 10
    case liteSlow = 11
    case narrowFast = 12
    case narrowSlow = 13

    /// Presets that should appear in user-facing pickers (LoRa config,
    /// discovery scan). The Lite (125 kHz EU 866) and Narrow (62.5 kHz
    /// EU 868) presets are intentionally hidden from selection for now —
    /// they still exist as cases so a radio already configured on one of
    /// them round-trips through protobuf and renders the correct label in
    /// node lists, but the user can't pick them yet. Add the matching
    /// cases back to this array when the firmware/UI rollout is ready.
    static var userSelectable: [ModemPresets] {
        allCases.filter { preset in
            switch preset {
            case .liteFast, .liteSlow, .narrowFast, .narrowSlow:
                return false
            default:
                return true
            }
        }
    }

    var id: Int { self.rawValue }

    var description: String {
        switch self {
        case .longFast:
            return "Long Range - Fast".localized
        case .longSlow:
            return "Long Range - Slow".localized
        case .longModerate:
            return "Long Range - Moderate".localized
        case .longTurbo:
            return "Long Range - Turbo".localized
        case .medSlow:
            return "Medium Range - Slow".localized
        case .medFast:
            return "Medium Range - Fast".localized
        case .shortSlow:
            return "Short Range - Slow".localized
        case .shortFast:
            return "Short Range - Fast".localized
        case .shortTurbo:
            return "Short Range - Turbo".localized
        case .liteFast:
            return "Lite - Fast".localized
        case .liteSlow:
            return "Lite - Slow".localized
        case .narrowFast:
            return "Narrow - Fast".localized
        case .narrowSlow:
            return "Narrow - Slow".localized
        }
    }

    var name: String {
        switch self {
        case .longFast:
            return "LongFast"
        case .longSlow:
            return "LongSlow"
        case .longModerate:
            return "LongModerate"
        case .longTurbo:
            return "LongTurbo"
        case .medSlow:
            return "MediumSlow"
        case .medFast:
            return "MediumFast"
        case .shortSlow:
            return "ShortSlow"
        case .shortFast:
            return "ShortFast"
        case .shortTurbo:
            return "ShortTurbo"
        case .liteFast:
            return "LiteFast"
        case .liteSlow:
            return "LiteSlow"
        case .narrowFast:
            return "NarrowFast"
        case .narrowSlow:
            return "NarrowSlow"
        }
    }

    func snrLimit() -> Float {
        switch self {
        case .longFast:
            return -17.5
        case .longSlow:
            return -7.5
        case .longTurbo:
            return -12.5
        case .longModerate:
            return -17.5
        case .medSlow:
            return -15
        case .medFast:
            return -12.5
        case .shortSlow:
            return -10
        case .shortFast:
            return -7.5
        case .shortTurbo:
            return -7.5
        case .liteFast:
            // Lite presets are 125kHz, comparable link-budget to LongFast / ShortSlow.
            // Conservative middle-of-the-road SNR floor pending field data.
            return -12.5
        case .liteSlow:
            return -15
        case .narrowFast:
            // 62.5kHz narrow presets — similar to shortSlow link budget.
            return -10
        case .narrowSlow:
            return -12.5
        }
    }

    func protoEnumValue() -> Config.LoRaConfig.ModemPreset {
        switch self {
        case .longFast:
            return Config.LoRaConfig.ModemPreset.longFast
        case .longSlow:
            return Config.LoRaConfig.ModemPreset.longSlow
        case .longModerate:
            return Config.LoRaConfig.ModemPreset.longModerate
        case .longTurbo:
            return Config.LoRaConfig.ModemPreset.longTurbo
        case .medSlow:
            return Config.LoRaConfig.ModemPreset.mediumSlow
        case .medFast:
            return Config.LoRaConfig.ModemPreset.mediumFast
        case .shortSlow:
            return Config.LoRaConfig.ModemPreset.shortSlow
        case .shortFast:
            return Config.LoRaConfig.ModemPreset.shortFast
        case .shortTurbo:
            return Config.LoRaConfig.ModemPreset.shortTurbo
        case .liteFast:
            return Config.LoRaConfig.ModemPreset.liteFast
        case .liteSlow:
            return Config.LoRaConfig.ModemPreset.liteSlow
        case .narrowFast:
            return Config.LoRaConfig.ModemPreset.narrowFast
        case .narrowSlow:
            return Config.LoRaConfig.ModemPreset.narrowSlow
        }
    }
}
