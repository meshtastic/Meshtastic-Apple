//
//  RegionCodes+FirmwareLocale.swift
//  Meshtastic
//

import Foundation

extension RegionCodes {
    static let latinScriptRegions: Set<RegionCodes> = [
        .us, .eu433, .eu868, .anz, .anz433, .in, .nz865, .my433, .my919,
        .sg923, .ph433, .ph868, .ph915, .kz433, .kz863, .np865, .br902,
        .itu12M, .itu232M, .eu866, .eu874, .eu917, .euN868, .lora24
    ]

    var prefersLocalizedFontFirmware: Bool {
        !Self.latinScriptRegions.contains(self) && self != .unset
    }

    var firmwareLocaleTagCandidates: [String] {
        let primary = topic.uppercased()
        var tags: [String] = []

        func append(_ value: String?) {
            guard let value, !value.isEmpty, !tags.contains(value) else { return }
            tags.append(value)
        }

        append(primary)
        append(primary.lowercased())
        append(primary.replacingOccurrences(of: "_", with: "-"))
        append(primary.lowercased().replacingOccurrences(of: "_", with: "-"))

        if let firstSegment = primary.split(separator: "_").first.map(String.init) {
            append(firstSegment)
            append(firstSegment.lowercased())
        }

        return tags
    }
}
