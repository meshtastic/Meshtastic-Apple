//
//  BootloaderFaultNotice.swift
//  Meshtastic
//
//  The Last-Fault line a bootloader drive reported, shown on the bootloader
//  maintenance sheets so a report of a stuck radio carries the fault id and PC.
//

import OSLog
import SwiftUI

struct BootloaderFaultNotice: View {
	let fault: BootloaderFault

	var body: some View {
		Label {
			VStack(alignment: .leading, spacing: 4) {
				Text("The bootloader recorded a fault before this boot. Include this line when you report a problem with this radio.")
					.fixedSize(horizontal: false, vertical: true)
				Text(verbatim: "Last-Fault: \(fault.summary)")
					.font(.caption.monospaced())
					.textSelection(.enabled)
			}
		} icon: {
			Image(systemName: "exclamationmark.octagon")
				.foregroundStyle(.orange)
		}
		.font(.caption)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	/// Parses the fault from the drive's INFO_UF2.TXT and writes it to the app log at
	/// `.error`, the lowest level OSLogStore keeps, so it reaches an exported log.
	static func record(fromInfoText text: String) -> BootloaderFault? {
		guard let fault = OTAFIXBootloader.parseLastFault(fromInfoText: text) else { return nil }
		Logger.services.error("Bootloader Last-Fault: \(fault.summary, privacy: .public)")
		return fault
	}
}

#Preview {
	BootloaderFaultNotice(fault: BootloaderFault(id: 0x1, pc: 0xf4a2c, info: 0x8))
		.padding()
}
